CREATE TABLE locales (
  code VARCHAR(10) PRIMARY KEY,
  name VARCHAR(100) NOT NULL
);

INSERT INTO locales (code, name) VALUES
  ('en', 'English'),
  ('pt-BR', 'Português');

SELECT code, name
FROM locales
WHERE code = 'pt-BR'
   OR code LIKE 'pt-%'
ORDER BY code ASC
LIMIT 1;
