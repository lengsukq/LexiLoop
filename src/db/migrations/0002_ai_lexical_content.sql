ALTER TABLE word_contents ADD COLUMN word_family_json TEXT NOT NULL DEFAULT '[]';
ALTER TABLE word_contents ADD COLUMN confused_words_json TEXT NOT NULL DEFAULT '[]';
ALTER TABLE word_contents ADD COLUMN roots_json TEXT NOT NULL DEFAULT '[]';
ALTER TABLE word_contents ADD COLUMN affixes_json TEXT NOT NULL DEFAULT '[]';
ALTER TABLE word_contents ADD COLUMN summary_json TEXT NOT NULL DEFAULT '{"shortDefinition":null,"translation":null,"cefrLevel":null,"frequency":null}';
ALTER TABLE word_contents ADD COLUMN learning_json TEXT NOT NULL DEFAULT '{"pronunciationTip":null,"mnemonic":null,"commonMistakes":[]}';
ALTER TABLE provider_attempts ADD COLUMN metadata_json TEXT;
