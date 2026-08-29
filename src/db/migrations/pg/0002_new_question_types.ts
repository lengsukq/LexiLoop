export const PG_NEW_QUESTION_TYPES_SQL = `
DO $$ BEGIN
  ALTER TABLE study_session_items DROP CONSTRAINT IF EXISTS study_session_items_question_type_check;
EXCEPTION WHEN undefined_object THEN NULL; END $$;
ALTER TABLE study_session_items ADD CONSTRAINT study_session_items_question_type_check
  CHECK (question_type IN ('EN_TO_ZH','EN_TO_ZH_CHOICE','ZH_TO_EN_CHOICE','ZH_TO_EN_SPELLING','LISTENING_SPELLING','CLOZE_SENTENCE','LISTENING_CHOICE','LETTER_BANK'));
`;
