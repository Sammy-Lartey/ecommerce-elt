-- read-only login for bi tools, limited to the gold schema


create user bi_reader password '${bi_password}';
grant usage on schema marts to bi_reader;
grant select on all tables in schema marts to bi_reader;
alter default privileges in schema marts grant select on tables to bi_reader;