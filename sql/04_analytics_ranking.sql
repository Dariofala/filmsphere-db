-- =====================================================================
-- FilmSphere - 04 Data Analytic 1 (cap. 11.1)
-- Classifica dei 10 film più visti negli ultimi 14 giorni, per server CDN e per abbonamento,
-- con il formato a risoluzione più alta disponibile per ciascun film (utile per decidere cosa tenere in cache)
-- =====================================================================
USE FilmSphere;
SET NAMES utf8mb4;

DROP PROCEDURE IF EXISTS RankFilmPerArea;
DELIMITER $$
CREATE PROCEDURE RankFilmPerArea(IN _ID_Input INT)
BEGIN
	-- prime 10 posizioni dei film visti tramite il server X (un server per continente) in ordine di numero di visualizzazioni
	WITH VisteNelServer AS (
		-- visualizzazioni degli ultimi 14 giorni avvenute durante una connessione al server X
		SELECT C.ID_Film
		FROM Cronologia C
		WHERE C.Data_visualizzazione > CURRENT_DATE() - INTERVAL 14 DAY
		  AND EXISTS (
					SELECT 1
					FROM Connessione K
					WHERE K.CodFiscale = C.CodFiscale
					  AND K.ID_server = _ID_Input
					  AND C.Data_visualizzazione BETWEEN DATE(K.Inizio_connessione)
													 AND DATE(COALESCE(K.Fine_connessione, NOW()))
					)
	),
	Classifica AS (
		SELECT F.ID_Film, F.Titolo, COUNT(*) AS Visualizzazioni,
			   RANK() OVER (ORDER BY COUNT(*) DESC) AS Posizione
		FROM VisteNelServer V
			 INNER JOIN Film F ON F.ID_Film = V.ID_Film
		GROUP BY F.ID_Film, F.Titolo
	)
	SELECT T.Posizione, T.ID_Film, T.Titolo, T.Visualizzazioni, R.Codice_formato
	FROM Classifica T
		 INNER JOIN Rilascio R ON R.ID_Film = T.ID_Film
		 INNER JOIN Formato F ON F.Codice_formato = R.Codice_formato
	WHERE T.Posizione <= 10
	  AND F.Risoluzione = (
							SELECT MAX(F1.Risoluzione)
							FROM Formato F1
								 INNER JOIN Rilascio R1 ON R1.Codice_formato = F1.Codice_formato
							WHERE R1.ID_Film = T.ID_Film
						  )
	ORDER BY T.Posizione, T.Titolo;
END $$
DELIMITER ;

/*
CALL RankFilmPerArea(1);
CALL RankFilmPerArea(2);
CALL RankFilmPerArea(3);
CALL RankFilmPerArea(4);
CALL RankFilmPerArea(5);
CALL RankFilmPerArea(6);
*/


DROP PROCEDURE IF EXISTS RankFilmPerAbbonamento;
DELIMITER $$
CREATE PROCEDURE RankFilmPerAbbonamento(IN _NomeAbbonamentoX VARCHAR(50))
BEGIN
	-- prime 10 posizioni dei film visti dagli utenti iscritti all'abbonamento X negli ultimi 14 giorni
	WITH Classifica AS (
		SELECT F.ID_Film, F.Titolo, COUNT(*) AS Visualizzazioni,
			   RANK() OVER (ORDER BY COUNT(*) DESC) AS Posizione
		FROM Cronologia C
			 INNER JOIN Iscrizione I ON I.CodFiscale = C.CodFiscale
			 INNER JOIN Film F ON F.ID_Film = C.ID_Film
		WHERE I.Nome = _NomeAbbonamentoX
		  AND C.Data_visualizzazione > CURRENT_DATE() - INTERVAL 14 DAY
		GROUP BY F.ID_Film, F.Titolo
	)
	SELECT T.Posizione, T.ID_Film, T.Titolo, T.Visualizzazioni, R.Codice_formato
	FROM Classifica T
		 INNER JOIN Rilascio R ON R.ID_Film = T.ID_Film
		 INNER JOIN Formato F ON F.Codice_formato = R.Codice_formato
	WHERE T.Posizione <= 10
	  AND F.Risoluzione = (
							SELECT MAX(F1.Risoluzione)
							FROM Formato F1
								 INNER JOIN Rilascio R1 ON R1.Codice_formato = F1.Codice_formato
							WHERE R1.ID_Film = T.ID_Film
						  )
	ORDER BY T.Posizione, T.Titolo;
END $$
DELIMITER ;

/*
CALL RankFilmPerAbbonamento("Basic");
CALL RankFilmPerAbbonamento("Premium");
CALL RankFilmPerAbbonamento("Pro");
CALL RankFilmPerAbbonamento("Deluxe");
CALL RankFilmPerAbbonamento("Ultimate");
*/
