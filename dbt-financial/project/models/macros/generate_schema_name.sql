{% macro generate_schema_name(custom_schema_name, node) %}

    {{ log("CUSTOM generate_schema_name EJECUTADO | custom=" ~ custom_schema_name ~ " | target=" ~ target.schema, info=True) }}

    {% if custom_schema_name is none %}
        {{ target.schema }}
    {% else %}
        {{ custom_schema_name }}
    {% endif %}

{% endmacro %}