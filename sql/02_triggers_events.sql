-- =====================================================================
-- FilmSphere - 02 Trigger ed Event (vincoli di integrità generici, cap. 9)
-- =====================================================================
USE FilmSphere;
SET NAMES utf8mb4;

-- ---------------------------------------------------------------------
-- FUNZIONI DI SUPPORTO
-- ---------------------------------------------------------------------

-- Converte la qualità testuale in un punteggio confrontabile
-- SD(1), HD(2), FULLHD(3), 4K(4); accetta anche varianti come "FULL HD"
DROP FUNCTION IF EXISTS PunteggioQualita;
DELIMITER $$
CREATE FUNCTION PunteggioQualita(_Qualita VARCHAR(10))
RETURNS INT
DETERMINISTIC NO SQL
BEGIN
	RETURN CASE UPPER(REPLACE(_Qualita, ' ', ''))
				WHEN 'SD'     THEN 1
				WHEN 'HD'     THEN 2
				WHEN 'FULLHD' THEN 3
				WHEN '4K'     THEN 4
				ELSE NULL
		   END;
END $$
DELIMITER ;

-- Restituisce il server CDN più vicino a un paese (distanza calcolata sulle coordinate).
-- _ConsideraCarico = TRUE : considera solo i server con meno di 50 connessioni attive
--                           (sopra questa soglia il server è in stato "Pessimo", vedi 9.2)
-- _ServerEscluso          : server da non considerare (NULL = nessuno)
-- Restituisce NULL se nessun server soddisfa le condizioni.
DROP FUNCTION IF EXISTS ServerPiuVicino;
DELIMITER $$
CREATE FUNCTION ServerPiuVicino(_Paese VARCHAR(50), _ConsideraCarico BOOL, _ServerEscluso INT)
RETURNS INT
READS SQL DATA
BEGIN
	RETURN (
		SELECT S.ID_server
		FROM ServerCDN S
			 INNER JOIN AreaGeografica AreaServer ON AreaServer.Paese = S.Paese
			 CROSS JOIN AreaGeografica AreaUtente
		WHERE AreaUtente.Paese = _Paese
		  AND (_ServerEscluso IS NULL OR S.ID_server <> _ServerEscluso)
		  AND (NOT _ConsideraCarico OR (
				SELECT COUNT(*)
				FROM Connessione C
				WHERE C.ID_server = S.ID_server AND C.Fine_connessione IS NULL
			  ) < 50)
		ORDER BY POW(AreaUtente.Latitudine  - AreaServer.Latitudine, 2)
			   + POW(AreaUtente.Longitudine - AreaServer.Longitudine, 2),
				 S.ID_server
		LIMIT 1
	);
END $$
DELIMITER ;

-- Restituisce il genere più presente nella cronologia di un utente (NULL se cronologia vuota)
DROP FUNCTION IF EXISTS GenerePreferitoUtente;
DELIMITER $$
CREATE FUNCTION GenerePreferitoUtente(_CodFiscale CHAR(50))
RETURNS VARCHAR(25)
READS SQL DATA
BEGIN
	RETURN (
		SELECT F.Genere
		FROM Cronologia C
			 INNER JOIN Film F ON F.ID_Film = C.ID_Film
		WHERE C.CodFiscale = _CodFiscale
		GROUP BY F.Genere
		ORDER BY COUNT(*) DESC, F.Genere
		LIMIT 1
	);
END $$
DELIMITER ;

-- Aggiorna lo stato di un server in base alle connessioni attive (usata da 9.2)
DROP PROCEDURE IF EXISTS AggiornaStatoServer;
DELIMITER $$
CREATE PROCEDURE AggiornaStatoServer(IN _ID_server INT)
BEGIN
	DECLARE NumeroConnessioni INT;

	SET NumeroConnessioni = (
							SELECT COUNT(*)
							FROM Connessione
							WHERE ID_server = _ID_server AND Fine_connessione IS NULL
							);

	UPDATE ServerCDN
	SET Stato = CASE
					WHEN NumeroConnessioni < 25 THEN 'Buono'
					WHEN NumeroConnessioni < 50 THEN 'Regolare'
					ELSE 'Pessimo'
				END
	WHERE ID_server = _ID_server;
END $$
DELIMITER ;


-- ---------------------------------------------------------------------
-- TRIGGER
-- ---------------------------------------------------------------------

-- 9.1
-- Anno produzione film deve essere uguale al minimo anno (data uscita) di quel film in un qualsiasi formato
-- Il trigger scatta sull'inserimento di un Rilascio: è in quel momento che si conosce la data di uscita del film nel formato
DROP TRIGGER IF EXISTS ControlloDataFilm;
DELIMITER $$
CREATE TRIGGER ControlloDataFilm
AFTER INSERT ON Rilascio FOR EACH ROW
BEGIN
	UPDATE Film
	SET Anno_Produzione = YEAR(NEW.Data_uscita)
	WHERE ID_Film = NEW.ID_Film
	  AND Anno_Produzione > YEAR(NEW.Data_uscita);
END $$
DELIMITER ;

-- 9.2
-- Aggiornare lo stato dei server in funzione del numero di connessioni
-- (sia all'apertura di una connessione, sia alla sua chiusura o a un cambio di server)
DROP TRIGGER IF EXISTS StatoServerCDN;
DELIMITER $$
CREATE TRIGGER StatoServerCDN
AFTER INSERT ON Connessione FOR EACH ROW
BEGIN
	CALL AggiornaStatoServer(NEW.ID_server);
END $$
DELIMITER ;

DROP TRIGGER IF EXISTS StatoServerCDNAggiornamento;
DELIMITER $$
CREATE TRIGGER StatoServerCDNAggiornamento
AFTER UPDATE ON Connessione FOR EACH ROW
BEGIN
	CALL AggiornaStatoServer(NEW.ID_server);
	IF OLD.ID_server <> NEW.ID_server THEN
		CALL AggiornaStatoServer(OLD.ID_server);
	END IF;
END $$
DELIMITER ;


-- 9.3
-- Vincoli per il popolamento della tabella Connessione
DROP TRIGGER IF EXISTS PopolamentoConnessione;
DELIMITER $$
CREATE TRIGGER PopolamentoConnessione
BEFORE INSERT ON Connessione FOR EACH ROW
BEGIN
	DECLARE AbbonamentoUtente VARCHAR(50);
	DECLARE IPArea INT;

	-- l'utente deve essere presente tra gli utenti
	IF NOT EXISTS (SELECT 1 FROM Utente WHERE CodFiscale = NEW.CodFiscale) THEN
		SIGNAL SQLSTATE '45000'
		SET MESSAGE_TEXT = "Utente non presente in piattaforma, connessione non eseguibile";
	END IF;

	-- Il paese deve essere presente tra le aree geografiche del database
	IF NOT EXISTS (SELECT 1 FROM AreaGeografica WHERE Paese = NEW.Paese) THEN
		SIGNAL SQLSTATE '45000'
		SET MESSAGE_TEXT = "Paese non riconosciuto, connessione non eseguibile";
	END IF;

	-- dispositivo deve essere uno tra Smartphone, Tablet, Computer, SmartTV
	IF NEW.Dispositivo NOT IN ('Smartphone', 'Tablet', 'Computer', 'SmartTV') THEN
		SIGNAL SQLSTATE '45000'
		SET MESSAGE_TEXT = "Il dispositivo usato per la connessione non è riconosciuto, connessione non eseguibile";
	END IF;

	-- Controllo che il paese da cui viene effettuata la connessione sia valido in base alla restrizione dell'abbonamento dell'utente
	-- (la tabella Restrizione elenca i paesi in cui ogni abbonamento è disponibile)
	SET AbbonamentoUtente = (
							SELECT Nome
							FROM Iscrizione
							WHERE CodFiscale = NEW.CodFiscale
							);

	IF NOT EXISTS (
					SELECT 1
					FROM Restrizione R
					WHERE R.Nome = AbbonamentoUtente AND R.Paese = NEW.Paese
				  ) THEN
		SIGNAL SQLSTATE '45000'
		SET MESSAGE_TEXT = "La connessione non è eseguibile a causa delle restrizioni dell'abbonamento";
	END IF;

	-- se Fine_connessione non è NULL allora deve essere successiva a Inizio_connessione
	IF NEW.Fine_connessione IS NOT NULL AND NEW.Fine_connessione < NEW.Inizio_connessione THEN
		SIGNAL SQLSTATE '45000'
		SET MESSAGE_TEXT = "La fine della connessione non può essere antecedente all'inizio della stessa";
	END IF;

	-- Ogni dispositivo ha il suo indirizzo IP quindi se si effettua una connessione con un dispositivo già utilizzato questo deve avere
	-- il proprio indirizzo IP indifferentemente dall'IP inserito in ingresso
	IF EXISTS (
				SELECT 1
				FROM Connessione
				WHERE CodFiscale = NEW.CodFiscale AND Dispositivo = NEW.Dispositivo
			  ) THEN
		SET NEW.Indirizzo_IP = (
								SELECT Indirizzo_IP
								FROM Connessione
								WHERE Dispositivo = NEW.Dispositivo
								  AND CodFiscale = NEW.CodFiscale
								ORDER BY Inizio_connessione
								LIMIT 1
							   );
	ELSE
		-- il prefisso dell'indirizzo IP deve corrispondere a quello dell'area geografica (vedi glossario: IP_area)
		SET IPArea = (SELECT IP_area FROM AreaGeografica WHERE Paese = NEW.Paese);
		IF NEW.Indirizzo_IP / 1000000000 < IPArea OR NEW.Indirizzo_IP / 1000000000 >= IPArea + 1 THEN
			SIGNAL SQLSTATE '45000'
			SET MESSAGE_TEXT = "L'indirizzo IP non corrisponde all'area geografica della connessione, connessione non eseguibile";
		END IF;
	END IF;

	-- 9.9 Scelta server CDN: la connessione viene allacciata al server più vicino che non sia sovraccarico,
	-- indifferentemente dal server indicato in ingresso. Se tutti i server sono sovraccarichi si usa il più vicino.
	SET NEW.ID_server = COALESCE(
								ServerPiuVicino(NEW.Paese, TRUE, NULL),
								ServerPiuVicino(NEW.Paese, FALSE, NULL)
								);
END $$
DELIMITER ;

-- 9.4
-- L’attributo Massimo_ore_mensili deve essere soddisfatto e il film deve essere visualizzabile
DROP TRIGGER IF EXISTS ControlloVisualizzazione;
DELIMITER $$
CREATE TRIGGER ControlloVisualizzazione
BEFORE INSERT ON Cronologia FOR EACH ROW
BEGIN
	CALL FilmVisualizzabile(NEW.ID_Film, NEW.CodFiscale);   -- procedura definita in 03_operations.sql (7.6)
END $$
DELIMITER ;

-- 9.5
-- L’attributo Eta_minima deve essere soddisfatto
DROP TRIGGER IF EXISTS ControlloEtaMinima;
DELIMITER $$
CREATE TRIGGER ControlloEtaMinima
BEFORE INSERT ON Iscrizione FOR EACH ROW
BEGIN
	DECLARE EtaUtente INT DEFAULT 0;
	DECLARE EtaAbbonamento INT DEFAULT 18;

	SET EtaUtente = (
					SELECT TIMESTAMPDIFF(YEAR, Data_nascita, CURRENT_DATE())
					FROM Utente
					WHERE CodFiscale = NEW.CodFiscale
					);

	SET EtaAbbonamento = (
						SELECT Eta_minima
						FROM Abbonamento
						WHERE Nome = NEW.Nome
						);

	IF EtaAbbonamento > EtaUtente THEN
		SIGNAL SQLSTATE '45000'
		SET MESSAGE_TEXT = "L'utente non ha l'età sufficiente per iscriversi a tale abbonamento";
	END IF;
END $$
DELIMITER ;

-- 9.6
-- Data una richiesta di visualizzazione di un film nel formato disponibile per l'abbonamento dell'utente,
-- controllare che quel film sia disponibile nel luogo dove avviene la connessione:
-- deve esistere almeno un formato video del film disponibile nel paese della connessione
-- con qualità non superiore a quella consentita dall'abbonamento dell'utente
DROP TRIGGER IF EXISTS ControlloFormato;
DELIMITER $$
CREATE TRIGGER ControlloFormato
BEFORE INSERT ON Cronologia FOR EACH ROW
BEGIN
	DECLARE LuogoConnessione VARCHAR(50);
	DECLARE PunteggioQualitaUtente INT;

	-- ricerco il paese da cui l'utente ha effettuato la connessione
	SET LuogoConnessione = (
							SELECT Paese
							FROM Connessione
							WHERE CodFiscale = NEW.CodFiscale
							  AND DATE(Inizio_connessione) = NEW.Data_visualizzazione
							ORDER BY Inizio_connessione
							LIMIT 1
							);

	-- ricerco la qualità massima disponibile per l'abbonamento dell'utente e la converto in numero
	SET PunteggioQualitaUtente = (
								SELECT PunteggioQualita(A.Qualita_contenuti)
								FROM Abbonamento A
									 INNER JOIN Iscrizione I ON I.Nome = A.Nome
								WHERE I.CodFiscale = NEW.CodFiscale
								);

	-- il film deve avere almeno un formato video disponibile nel luogo della connessione
	IF NOT EXISTS (
					SELECT 1
					FROM Rilascio R
						 INNER JOIN Formato F ON F.Codice_formato = R.Codice_formato
						 INNER JOIN Disponibilita D ON D.Codice_formato = F.Codice_formato
					WHERE R.ID_Film = NEW.ID_Film
					  AND F.Tipo_formato <> 'Audio'
					  AND D.Paese = LuogoConnessione
				  ) THEN
		SIGNAL SQLSTATE '45000'
		SET MESSAGE_TEXT = "Il formato del film non è disponibile nel luogo della connessione";
	END IF;

	-- tra i formati disponibili, almeno uno deve rispettare la qualità dell'abbonamento
	IF NOT EXISTS (
					SELECT 1
					FROM Rilascio R
						 INNER JOIN Formato F ON F.Codice_formato = R.Codice_formato
						 INNER JOIN Disponibilita D ON D.Codice_formato = F.Codice_formato
					WHERE R.ID_Film = NEW.ID_Film
					  AND F.Tipo_formato <> 'Audio'
					  AND D.Paese = LuogoConnessione
					  AND PunteggioQualita(F.Qualita) <= PunteggioQualitaUtente
				  ) THEN
		SIGNAL SQLSTATE '45000'
		SET MESSAGE_TEXT = "La qualità contenuti dell'abbonamento dell'utente non consente di visualizzare il film";
	END IF;
END $$
DELIMITER ;


-- 9.7
-- Controllare che formato video sia di tipo: video, audio o audiovideo
DROP TRIGGER IF EXISTS FormatoInserito;
DELIMITER $$
CREATE TRIGGER FormatoInserito
BEFORE INSERT ON Formato FOR EACH ROW
BEGIN
	IF NEW.Tipo_formato NOT IN ('Video', 'Audio', 'AudioVideo') THEN
		SIGNAL SQLSTATE '45000'
		SET MESSAGE_TEXT = "Il tipo di formato inserito è errato";
	END IF;
END $$
DELIMITER ;


-- 9.8
-- Creazione di un nuovo utente implica creazione di una cache per lui sul server più vicino
DROP TRIGGER IF EXISTS CacheUtente;
DELIMITER $$
CREATE TRIGGER CacheUtente
AFTER INSERT ON Utente FOR EACH ROW
BEGIN
	IF NOT EXISTS (SELECT 1 FROM Cache WHERE CodFiscale = NEW.CodFiscale) THEN
		INSERT INTO Cache(CodFiscale, ID_server)
		VALUES (NEW.CodFiscale, ServerPiuVicino(NEW.Paese, FALSE, NULL));
	END IF;
END $$
DELIMITER ;


-- 9.9
-- Scelta server CDN
-- Quando un utente richiede di visualizzare un film, una funzionalità, sceglie il server del CDN più vicino all’utente,
-- per ridurre i tempi di buffering e migliorare l’esperienza di visione. Inoltre, questa funzionalità considera le informazioni sul traffico di rete e sulle prestazioni
-- dei vari server del CDN, al fine di garantire che l’utente riceva il contenuto dal server più opportuno in quel momento, non solo in ottica di prossimità,
-- ma anche in termini di bilanciamento del carico.
-- Durante la visione di un film da parte di un utente, il server CDN può cambiare.
-- Questo può avvenire per diversi motivi, come ad esempio il sovraccarico del server, o il sopraggiungere di problemi di connessione.
-- Il sistema di CDN è progettato per scegliere automaticamente il server (alternativo) più opportuno,
-- cioè vicino all’utente e in grado di garantire una visualizzazione fluida e senza interruzioni dato il suo livello di carico.
--
-- Implementazione:
--  a) alla creazione di una connessione il server viene scelto dal trigger 9.3 (più vicino e non sovraccarico);
--  b) l'event BilanciamentoServer sposta periodicamente, da ogni server sovraccarico (>= 50 connessioni attive),
--     la connessione attiva più lontana (a parità di distanza la più vecchia) sul server alternativo più vicino.
--     Lo spostamento è fatto da un event perché MySQL non consente a un trigger di modificare la tabella su cui è definito.
DROP TRIGGER IF EXISTS BilanciamentoServer;
DROP EVENT IF EXISTS BilanciamentoServer;
DELIMITER $$
CREATE EVENT BilanciamentoServer
ON SCHEDULE EVERY 5 MINUTE
DO
BEGIN
	DECLARE finito INT DEFAULT 0;
	DECLARE ServerX INT;
	DECLARE Salva_Inizio_connessione DATETIME;
	DECLARE Salva_Indirizzo_IP BIGINT;
	DECLARE Salva_Paese VARCHAR(50);
	DECLARE ID_server_vicino INT;

	DECLARE CursoreServer CURSOR FOR
		SELECT ID_server
		FROM Connessione
		WHERE Fine_connessione IS NULL
		GROUP BY ID_server
		HAVING COUNT(*) >= 50;

	DECLARE CONTINUE HANDLER FOR NOT FOUND SET finito = 1;

	OPEN CursoreServer;

	scorri: LOOP
		FETCH CursoreServer INTO ServerX;
		IF finito = 1 THEN
			LEAVE scorri;
		END IF;

		-- connessione attiva più lontana dal server sovraccarico; a parità di distanza la più vecchia
		SELECT C.Inizio_connessione, C.Indirizzo_IP, C.Paese
		INTO Salva_Inizio_connessione, Salva_Indirizzo_IP, Salva_Paese
		FROM Connessione C
			 INNER JOIN AreaGeografica AreaConnessione ON AreaConnessione.Paese = C.Paese
			 INNER JOIN ServerCDN S ON S.ID_server = C.ID_server
			 INNER JOIN AreaGeografica AreaServer ON AreaServer.Paese = S.Paese
		WHERE C.ID_server = ServerX AND C.Fine_connessione IS NULL
		ORDER BY POW(AreaConnessione.Latitudine  - AreaServer.Latitudine, 2)
			   + POW(AreaConnessione.Longitudine - AreaServer.Longitudine, 2) DESC,
				 C.Inizio_connessione ASC
		LIMIT 1;

		-- server alternativo più vicino alla connessione, escluso quello sovraccarico
		SET ID_server_vicino = ServerPiuVicino(Salva_Paese, TRUE, ServerX);

		-- se esiste un server alternativo non sovraccarico sposto la connessione
		-- (il trigger StatoServerCDNAggiornamento aggiorna lo stato di entrambi i server)
		IF ID_server_vicino IS NOT NULL THEN
			UPDATE Connessione
			SET ID_server = ID_server_vicino
			WHERE Inizio_connessione = Salva_Inizio_connessione
			  AND Indirizzo_IP = Salva_Indirizzo_IP;
		END IF;
	END LOOP scorri;

	CLOSE CursoreServer;
END $$
DELIMITER ;

-- 9.10
-- Aggiornare attributo Ore_rimanenti
DROP TRIGGER IF EXISTS AggiornaOreRimanenti;
DELIMITER $$
CREATE TRIGGER AggiornaOreRimanenti
AFTER INSERT ON Cronologia FOR EACH ROW
BEGIN
	-- il controllo sul numero di ore rimanenti dell'utente è effettuato dal trigger 9.4
	-- calcolo la durata del film in ore (con i decimali: Ore_rimanenti è DOUBLE)
	DECLARE DurataFilm DOUBLE;
	SET DurataFilm = (
					SELECT Durata
					FROM Film
					WHERE ID_Film = NEW.ID_Film
					) / 60;

	UPDATE Utente U
	SET U.Ore_rimanenti = U.Ore_rimanenti - DurataFilm
	WHERE U.CodFiscale = NEW.CodFiscale;
END $$
DELIMITER ;

-- 9.11
-- Aggiornare attributo Premi_vinti
DROP TRIGGER IF EXISTS AggiornaPremiVinti;
DELIMITER $$
CREATE TRIGGER AggiornaPremiVinti
AFTER INSERT ON Premio FOR EACH ROW
BEGIN
	UPDATE Regista
	SET Premi_vinti = Premi_vinti + 1
	WHERE CodFiscale IN (
						SELECT R.CodFiscale
						FROM Regia R
						WHERE R.ID_Film = NEW.ID_Film
						);
END $$
DELIMITER ;

-- 9.12
-- Un film può vincere un premio solo nell’anno in cui è uscito
DROP TRIGGER IF EXISTS VittoriaPremio;
DELIMITER $$
CREATE TRIGGER VittoriaPremio
BEFORE INSERT ON Premio FOR EACH ROW
BEGIN
	DECLARE Anno INT;
	SET Anno = (
				SELECT Anno_Produzione
				FROM Film
				WHERE ID_Film = NEW.ID_Film
				);
	IF Anno < NEW.Anno_vittoria THEN
		SIGNAL SQLSTATE '45000'
		SET MESSAGE_TEXT = "Premio non assegnabile, il film non è uscito nell'anno della vittoria";
	ELSEIF Anno > NEW.Anno_vittoria THEN
		SIGNAL SQLSTATE '45000'
		SET MESSAGE_TEXT = "Premio non assegnabile, il film è uscito dopo";
	END IF;
END $$
DELIMITER ;

-- 9.13
-- Nell'inserimento di un RatingPersonale aggiorna Peso_voto se il Rating è stato fatto da un Critico
DROP TRIGGER IF EXISTS ImportanzaVoto;
DELIMITER $$
CREATE TRIGGER ImportanzaVoto
BEFORE INSERT ON RatingPersonale FOR EACH ROW
BEGIN
	DECLARE UtenteCritico BOOL DEFAULT FALSE;
	SET UtenteCritico = (
						SELECT U.Critico
						FROM Utente U
						WHERE U.CodFiscale = NEW.CodFiscale
						);
	-- un valore NULL viene trattato come "non critico"
	IF IFNULL(UtenteCritico, FALSE) THEN
		SET NEW.Peso_voto = 3;
	ELSE
		SET NEW.Peso_voto = 1;
	END IF;
END $$
DELIMITER ;

-- ---------------------------------------------------------------------
-- EVENT  (richiedono: SET GLOBAL event_scheduler = ON;)
-- ---------------------------------------------------------------------

-- 9.14
-- Eliminare la cronologia di visualizzazione più vecchia di 6 mesi per ogni utente
DROP EVENT IF EXISTS PulisciCronologia;
DELIMITER $$
CREATE EVENT PulisciCronologia
ON SCHEDULE EVERY 1 DAY
STARTS "2022-01-01 23:55:00"
DO
BEGIN
	DELETE FROM Cronologia
	WHERE Data_visualizzazione < CURRENT_DATE() - INTERVAL 6 MONTH;
END $$
DELIMITER ;

-- 9.15
-- Caching: ogni settimana, per ogni cache, salva fino a 3 film del genere preferito dall'utente
-- che non ha ancora visto e che non sono già in cache, rispettando il limite di 15 film per cache (cap. 3.4)
DROP EVENT IF EXISTS Caching;
DELIMITER $$
CREATE EVENT Caching
ON SCHEDULE EVERY 7 DAY
STARTS "2022-01-01 23:55:00"
DO
BEGIN
	-- CREO UN CURSORE E SCORRO LA TABELLA CACHE, PRENDENDO UNA AD UNA LE COPPIE (UTENTE, SERVER)
	DECLARE finito INTEGER DEFAULT 0;
	DECLARE CodiceX CHAR(50);
	DECLARE ServerX INT;
	DECLARE GenerePreferito VARCHAR(25);
	DECLARE PostiLiberi INT;

	DECLARE Cursore CURSOR FOR
		SELECT CodFiscale, ID_server
		FROM Cache;

	DECLARE CONTINUE HANDLER FOR NOT FOUND
		SET finito = 1;

	OPEN Cursore;

	preleva: LOOP
		FETCH Cursore INTO CodiceX, ServerX;
		IF finito = 1 THEN
			LEAVE preleva;
		END IF;

		-- analizziamo il genere di film più visto dall'utente
		SET GenerePreferito = GenerePreferitoUtente(CodiceX);

		-- quanti film possono ancora essere salvati in questa cache (massimo 15)
		SET PostiLiberi = LEAST(3, 15 - (
										SELECT COUNT(*)
										FROM Salvataggio
										WHERE CodFiscale = CodiceX AND ID_server = ServerX
										));

		-- inseriamo dentro al salvataggio fino a 3 nuovi film, privilegiando quelli con valutazione più alta
		IF GenerePreferito IS NOT NULL AND PostiLiberi > 0 THEN
			INSERT INTO Salvataggio (ID_Film, ID_server, CodFiscale)
			SELECT F.ID_Film, ServerX, CodiceX
			FROM Film F
			WHERE F.Genere = GenerePreferito
			  AND NOT EXISTS (
							SELECT 1
							FROM Cronologia C
							WHERE C.ID_Film = F.ID_Film AND C.CodFiscale = CodiceX
							)
			  AND NOT EXISTS (
							SELECT 1
							FROM Salvataggio S
							WHERE S.ID_Film = F.ID_Film AND S.ID_server = ServerX AND S.CodFiscale = CodiceX
							)
			ORDER BY F.Valutazione DESC, F.ID_Film
			LIMIT PostiLiberi;
		END IF;
	END LOOP preleva;

	CLOSE Cursore;
END $$
DELIMITER ;


-- 9.16
-- Aggiornamento mensile delle ore di streaming rimanenti all'utente:
-- ogni utente riparte dal massimo di ore mensili previsto dal proprio abbonamento
DROP EVENT IF EXISTS AggiornamentoOreMensili;
DELIMITER $$
CREATE EVENT AggiornamentoOreMensili
ON SCHEDULE EVERY 1 MONTH
STARTS "2022-01-01 23:55:00"
DO
BEGIN
	UPDATE Utente U
		   INNER JOIN Iscrizione I ON I.CodFiscale = U.CodFiscale
		   INNER JOIN Abbonamento A ON A.Nome = I.Nome
	SET U.Ore_rimanenti = A.Massimo_ore_mensili;
END $$
DELIMITER ;
