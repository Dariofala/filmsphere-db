-- =====================================================================
-- FilmSphere - 05 Data Analytic 2 (cap. 11.2)
-- Calcolo automatico dell'attributo Valutazione di un film:
--   media pesata dei voti (i voti dei critici valgono 3 volte)
--   + 0.1 * importanza di ogni premio vinto
--   + 0.1 se i registi del film hanno vinto in totale più di 2 premi
--   (massimo 10)
-- =====================================================================
USE FilmSphere;
SET NAMES utf8mb4;

DROP FUNCTION IF EXISTS CalcoloValutazione;
DELIMITER $$
CREATE FUNCTION CalcoloValutazione(_ID_Input INT)
RETURNS FLOAT
READS SQL DATA
BEGIN
	DECLARE MediaValutazioni FLOAT DEFAULT 0;
	DECLARE SommaVoti INT DEFAULT 0;
	DECLARE NumVoti INT DEFAULT 0;
	DECLARE BonusPremi FLOAT DEFAULT 0;
	DECLARE BonusRegisti FLOAT DEFAULT 0;

	-- somma dei voti di quel film, pesati 3 volte se il voto è stato dato da un critico
	-- (Peso_voto vale 1 oppure 3, impostato dal trigger 9.13)
	SET SommaVoti = (
					SELECT SUM(R.Voto * R.Peso_voto)
					FROM RatingPersonale R
					WHERE R.ID_Film = _ID_Input
					);

	-- numero di voti, contando 3 volte quelli dei critici
	SET NumVoti = (
					SELECT SUM(R.Peso_voto)
					FROM RatingPersonale R
					WHERE R.ID_Film = _ID_Input
				  );

	-- senza voti il film non ha ancora una valutazione
	IF NumVoti IS NULL OR NumVoti = 0 THEN
		RETURN NULL;
	END IF;

	-- ogni premio vinto aggiunge 0.1 * la sua importanza
	SET BonusPremi = IFNULL(0.1 * (
									SELECT SUM(P.Importanza)
									FROM Premio P
									WHERE P.ID_Film = _ID_Input
								  ), 0);

	-- bonus se i registi del film hanno vinto in totale più di 2 premi
	IF (
		SELECT SUM(R1.Premi_vinti)
		FROM Regista R1
			 INNER JOIN Regia R2 ON R2.CodFiscale = R1.CodFiscale
		WHERE R2.ID_Film = _ID_Input
	   ) > 2 THEN
		SET BonusRegisti = 0.1;
	END IF;

	SET MediaValutazioni = (SommaVoti / NumVoti) + BonusPremi + BonusRegisti;

	-- la valutazione non può essere più di 10/10
	RETURN LEAST(MediaValutazioni, 10);
END $$
DELIMITER ;

-- quando viene inserito un nuovo rating si ricalcola la valutazione di quel film
DROP TRIGGER IF EXISTS ValutazioneFilm1;
DELIMITER $$
CREATE TRIGGER ValutazioneFilm1
AFTER INSERT ON RatingPersonale FOR EACH ROW
BEGIN
	UPDATE Film F
	SET F.Valutazione = CalcoloValutazione(NEW.ID_Film)
	WHERE F.ID_Film = NEW.ID_Film;
END $$
DELIMITER ;

-- quando viene inserito un nuovo premio si ricalcola la valutazione di quel film
-- (creato dopo AggiornaPremiVinti, quindi viene eseguito dopo l'aggiornamento di Premi_vinti)
DROP TRIGGER IF EXISTS ValutazioneFilm2;
DELIMITER $$
CREATE TRIGGER ValutazioneFilm2
AFTER INSERT ON Premio FOR EACH ROW
BEGIN
	UPDATE Film F
	SET F.Valutazione = CalcoloValutazione(NEW.ID_Film)
	WHERE F.ID_Film = NEW.ID_Film;
END $$
DELIMITER ;
