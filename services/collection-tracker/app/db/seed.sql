INSERT INTO series (name, kind, display_mode, viz_slug) VALUES
    ('Kagurabachi', 'manga', 'completionist', 'kagurabachi'),
    ('Web of Spider-Man', 'comic', 'curated', NULL)
ON CONFLICT (name) DO NOTHING;

INSERT INTO items (series_id, issue_number, display_name, status, owned_at)
SELECT s.id, v.issue_number, v.display_name, 'owned', NULL
FROM series s
CROSS JOIN (VALUES
    ('01', 'Volume 01'), ('02', 'Volume 02'), ('03', 'Volume 03'),
    ('04', 'Volume 04'), ('05', 'Volume 05'), ('06', 'Volume 06'),
    ('07', 'Volume 07')
) AS v(issue_number, display_name)
WHERE s.name = 'Kagurabachi'
ON CONFLICT (series_id, issue_number) DO NOTHING;

INSERT INTO items (series_id, issue_number, display_name, status, notes)
SELECT s.id, v.issue_number, v.display_name, 'not_for_sale', 'framed'
FROM series s
CROSS JOIN (VALUES
    ('1', '#1'), ('22', '#22'), ('47', '#47'), ('48', '#48')
) AS v(issue_number, display_name)
WHERE s.name = 'Web of Spider-Man'
ON CONFLICT (series_id, issue_number) DO NOTHING;
