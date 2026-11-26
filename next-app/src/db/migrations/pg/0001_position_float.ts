// study_session_items.position stores fractional midpoints produced by the
// adaptive follow-up inserter; DOUBLE PRECISION mirrors the SQLite data exactly.
export const PG_POSITION_FLOAT_SQL = `
ALTER TABLE study_session_items ALTER COLUMN position TYPE DOUBLE PRECISION;
`;
