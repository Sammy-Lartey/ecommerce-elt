set session authorization bi_reader;
select count(*) as rows_visible_to_bi_reader from marts.fct_transactions;
reset session authorization;