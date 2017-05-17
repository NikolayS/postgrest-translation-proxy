CREATE OR REPLACE FUNCTION v1.translate_array(source CHAR(2), target CHAR(2), q JSON)
RETURNS TEXT[] AS $BODY$
DECLARE
  rez TEXT[];
BEGIN
  SELECT
    CASE current_setting('translation_proxy.api.current_engine')
      WHEN 'google' THEN
        translation_proxy.google_translate_array( source, target, q )
      WHEN 'promt' THEN
        translation_proxy.promt_translate_array( source, target, ARRAY( SELECT json_array_elements_text(q) ) )
    END INTO rez;
    RETURN rez;
END;
$BODY$ LANGUAGE PLPGSQL SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION v1.translate_array(CHAR(2), CHAR(2), JSON) TO apiuser;
