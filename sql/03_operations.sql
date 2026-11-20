-- =====================================================================
-- FilmSphere - 03 Operazioni sui dati (cap. 7)
-- =====================================================================
USE FilmSphere;
SET NAMES utf8mb4;

-- 7.1	Visualizzare il numero di aree geografiche diverse da cui un utente ha effettuato almeno un accesso nel mese corrente
DROP FUNCTION IF EXISTS NumAreeDiverse;
DELIMITER $$
CREATE FUNCTION NumAreeDiverse(_Cod_Input CHAR(50))
RETURNS INT
READS SQL DATA
BEGIN
	DECLARE NumAree INT DEFAULT 0;

	SELECT COUNT(DISTINCT C.Paese) INTO NumAree
	FROM Connessione C
	WHERE C.CodFiscale = _Cod_Input
	  AND YEAR(C.Inizio_connessione)  = YEAR(CURRENT_DATE())
	  AND MONTH(C.Inizio_connessione) = MONTH(CURRENT_DATE());

	RETURN NumAree;
END $$
DELIMITER ;

-- 7.2 	Per ogni area geografica indicare nella data odierna qual è stato il tipo
-- 		di dispositivo su cui sono avvenute il maggior numero di connessioni
DROP PROCEDURE IF EXISTS DispositivoPiuUsato;
DELIMITER $$
CREATE PROCEDURE DispositivoPiuUsato()
BEGIN
	WITH TabellaConnessioni AS ( -- per ogni area e ogni dispositivo il numero di connessioni nella data odierna
		SELECT C1.Paese, C1.Dispositivo, COUNT(*) AS NumConnessioni
		FROM Connessione C1
		WHERE DATE(C1.Inizio_connessione) = CURRENT_DATE()
		GROUP BY C1.Paese, C1.Dispositivo
	)
	SELECT X.Paese, X.Dispositivo, X.NumConnessioni  -- in caso di parità vengono mostrati tutti i dispositivi a pari merito
	FROM TabellaConnessioni X
	WHERE X.NumConnessioni = (
								SELECT MAX(X1.NumConnessioni)
								FROM TabellaConnessioni X1
								WHERE X1.Paese = X.Paese
							 )
	ORDER BY X.Paese;
END $$
DELIMITER ;

-- 7.3 	Indicare gli utenti che hanno fatture in scadenza nei prossimi 10 giorni
DROP PROCEDURE IF EXISTS FattureInScadenza;
DELIMITER $$
CREATE PROCEDURE FattureInScadenza()
BEGIN
	SELECT U.Nome, U.Cognome, F.Codice, F.Scadenza_fattura
	FROM Utente U
		 INNER JOIN Fattura F ON F.CodFiscale = U.CodFiscale
	WHERE F.Data_pagamento IS NULL
	  AND F.Scadenza_fattura BETWEEN CURRENT_DATE() AND CURRENT_DATE() + INTERVAL 10 DAY
	ORDER BY F.Scadenza_fattura;
END $$
DELIMITER ;

-- 7.4 	Dato un regista, mostrare tutti i film diretti da quel regista che hanno
-- 		vinto un premio, negli ultimi 5 anni, includendo l’anno della vittoria
DROP PROCEDURE IF EXISTS FilmDelRegista;
DELIMITER $$
CREATE PROCEDURE FilmDelRegista(IN _Cod_Input CHAR(50))
BEGIN
	SELECT F.Titolo, P.Nome_premio, P.Anno_vittoria
	FROM Regia D
		 INNER JOIN Film F ON F.ID_Film = D.ID_Film
		 INNER JOIN Premio P ON P.ID_Film = F.ID_Film
	WHERE D.CodFiscale = _Cod_Input
	  AND P.Anno_vittoria >= YEAR(CURRENT_DATE()) - 5
	ORDER BY P.Anno_vittoria DESC;
END $$
DELIMITER ;


-- 7.5 	Visualizzazione dei 10 film più visti della settimana
DROP PROCEDURE IF EXISTS FilmPiuVistiSettimana;
DELIMITER $$
CREATE PROCEDURE FilmPiuVistiSettimana()
BEGIN
	WITH NumeroVisualizzazioni AS (	-- conto il numero di visualizzazioni dei film visti questa settimana
		SELECT C.ID_Film, F.Titolo, COUNT(*) AS VisualizzazioniPerFilm
		FROM Cronologia C
			 INNER JOIN Film F ON F.ID_Film = C.ID_Film
		WHERE C.Data_visualizzazione BETWEEN CURRENT_DATE() - INTERVAL 7 DAY AND CURRENT_DATE()
		GROUP BY C.ID_Film, F.Titolo
	),
	ClassificaVisualizzazioni AS ( -- classifica unica su tutti i film, basata sulle visualizzazioni
		SELECT Titolo, VisualizzazioniPerFilm,
			   RANK() OVER (ORDER BY VisualizzazioniPerFilm DESC) AS Posizione
		FROM NumeroVisualizzazioni
	)
	SELECT Posizione, Titolo, VisualizzazioniPerFilm   -- i 10 film più visti (a pari merito possono essere più di 10)
	FROM ClassificaVisualizzazioni
	WHERE Posizione <= 10
	ORDER BY Posizione, Titolo;
END $$
DELIMITER ;

-- 7.6	Dato un film e un utente dire se la durata del film è superiore alle ore mensili rimanenti nell’abbonamento di quell’utente
--      (usata anche dal trigger 9.4: genera un errore se il film non è visualizzabile)
DROP PROCEDURE IF EXISTS FilmVisualizzabile;
DELIMITER $$
CREATE PROCEDURE FilmVisualizzabile(IN _ID_Film INT, IN _CodFiscale CHAR(50))
BEGIN
	DECLARE durata DOUBLE DEFAULT 0;
	DECLARE rimanenti DOUBLE DEFAULT 0;

	IF NOT EXISTS (SELECT 1 FROM Film WHERE ID_Film = _ID_Film) THEN
		SIGNAL SQLSTATE '45000'
		SET MESSAGE_TEXT = 'Film non presente';
	END IF;

	IF NOT EXISTS (SELECT 1 FROM Utente WHERE CodFiscale = _CodFiscale) THEN
		SIGNAL SQLSTATE '45000'
		SET MESSAGE_TEXT = 'Nessun utente trovato';
	END IF;

	SET durata = (
				SELECT F1.Durata
				FROM Film F1
				WHERE F1.ID_Film = _ID_Film
				) / 60;   -- durata in ore

	SET rimanenti = (
					SELECT U1.Ore_rimanenti
					FROM Utente U1
					WHERE U1.CodFiscale = _CodFiscale
					);

	IF durata > rimanenti THEN
		SIGNAL SQLSTATE '45000'
		SET MESSAGE_TEXT = "Ore insufficienti, film non visualizzabile";
	END IF;
END $$
DELIMITER ;


-- 7.7 	Registrazione di un utente (Ore_rimanenti viene inizializzato a 0)
DROP PROCEDURE IF EXISTS RegistrazioneNuovoUtente;
DELIMITER $$
CREATE PROCEDURE RegistrazioneNuovoUtente(
	IN NewCodFiscale CHAR(50), IN NewPaese VARCHAR(50), IN NewNome VARCHAR(50), IN NewCognome VARCHAR(50),
	IN NewData_nascita DATE, IN NewCritico BOOL, IN NewEmail VARCHAR(100), IN NewPassword VARCHAR(50))
BEGIN
	-- si controlla che non siano già presenti il codice fiscale o l'email
	IF EXISTS (SELECT 1 FROM Utente WHERE CodFiscale = NewCodFiscale) THEN
		SIGNAL SQLSTATE '45000'
		SET MESSAGE_TEXT = 'Utente già presente';
	END IF;

	IF EXISTS (SELECT 1 FROM Utente WHERE Email = NewEmail) THEN
		SIGNAL SQLSTATE '45000'
		SET MESSAGE_TEXT = 'Email già registrata';
	END IF;

	-- si controlla che il paese sia presente nella tabella AreaGeografica
	IF NOT EXISTS (SELECT 1 FROM AreaGeografica WHERE Paese = NewPaese) THEN
		SIGNAL SQLSTATE '45000'
		SET MESSAGE_TEXT = 'Paese non presente';
	END IF;

	-- si inseriscono i dati del nuovo utente (il trigger 9.8 crea la sua cache)
	INSERT INTO Utente(CodFiscale, Paese, Nome, Cognome, Data_nascita, Critico, Email, Password, Ore_rimanenti)
	VALUES (NewCodFiscale, NewPaese, NewNome, NewCognome, NewData_nascita, NewCritico, NewEmail, NewPassword, 0);

	SELECT 'Nuovo utente inserito.' AS messaggio;
END $$
DELIMITER ;


-- 7.8	Dato un utente seleziona il genere più presente all’interno della sua cronologia e suggerisce
-- 		tutti i film presenti nel database di quel genere ad esclusione di quelli già visti
DROP PROCEDURE IF EXISTS RaccomandazioneContenuti;
DELIMITER $$
CREATE PROCEDURE RaccomandazioneContenuti(IN _CodFiscale CHAR(50))
BEGIN
	DECLARE GenerePreferito VARCHAR(25);

	-- analizziamo il genere di film più visto dall'utente (funzione definita in 02_triggers_events.sql)
	SET GenerePreferito = GenerePreferitoUtente(_CodFiscale);

	-- selezioniamo tutti i film di quel genere, a esclusione dei film già visti dall'utente
	SELECT F.ID_Film, F.Titolo, F.Valutazione
	FROM Film F
	WHERE F.Genere = GenerePreferito
	  AND NOT EXISTS (
					SELECT 1
					FROM Cronologia C
					WHERE C.ID_Film = F.ID_Film AND C.CodFiscale = _CodFiscale
					)
	ORDER BY F.Valutazione DESC, F.Titolo;
END $$
DELIMITER ;


-- 7.9	Indicare il/i regista/i che ha/hanno vinto più premi
DROP PROCEDURE IF EXISTS RegistaPiuVincente;
DELIMITER $$
CREATE PROCEDURE RegistaPiuVincente()
BEGIN
	SELECT R.Nome, R.Cognome, R.Premi_vinti
	FROM Regista R
	WHERE R.Premi_vinti = (
							SELECT MAX(R1.Premi_vinti)
							FROM Regista R1
						  );
END $$
DELIMITER ;
