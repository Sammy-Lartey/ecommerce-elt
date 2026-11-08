{% macro clean_text(column) %}
    nullif(nullif(trim({{ column }}), ''), 'N/A')
{% endmacro %}