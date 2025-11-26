{# dbt doesn't like us ref'ing in an operation so we fetch the info from the graph #}

{% macro upload_results(results) -%}

    {% if execute %}

        {# full list of datasets for reference: ['exposures', 'seeds', 'snapshots', 'invocations', 'sources', 'tests', 'models'] #}
        {% set datasets_to_load = [] %}
        {# only upload test data when tests were run #}
        {% if results | selectattr("node.resource_type", "equalto", "test") | list %}
            {# full list of datasets for reference: ['model_executions', 'seed_executions', 'test_executions', 'snapshot_executions'] #}
            {% set datasets_to_load = ['tests', 'test_executions'] + datasets_to_load %}
        {% else %}
            {{ log('no test data to upload to dbt artifacts', info=True) }}
        {% endif %}

        {% if datasets_to_load %}
            {# Check if the relation exists in BigQuery #}
            {% set relation = dbt_artifacts.get_relation(datasets_to_load[0]) %}
            {%- set bigquery_relation = adapter.get_relation(database=relation.database,
                                                            schema=relation.schema,
                                                            identifier=relation.identifier) -%}
            {% if bigquery_relation is none %}
                {{ exceptions.raise_compiler_error(
                    'dbt-artifacts  relation ' ~ relation ~
                    ' does not exist, so dbt-artifacts cannot write results. ' ~
                    'TIP: Run: dbt run -s package:dbt_artifacts'
                ) }}
                {{ return('') }}
            {% endif %}
        {% else %}
            {{ log('no datasets to upload to dbt artifacts', info=True) }}
        {% endif %}

        {# Upload each data set in turn #}
        {% for dataset in datasets_to_load %}

            {% do log("Uploading " ~ dataset.replace("_", " "), true) %}

            {# Get the results that need to be uploaded #}
            {% set objects = dbt_artifacts.get_dataset_content(dataset) %}

            {# Upload in chunks to reduce the query size #}
            {% if dataset == 'models' %}
                {% set upload_limit = 50 if target.type == 'bigquery' else 100 %}
            {% else %}
                {% set upload_limit = 300 if target.type == 'bigquery' else 5000 %}
            {% endif %}

            {# Loop through each chunk in turn #}
            {% for i in range(0, objects | length, upload_limit) -%}

                {# Get just the objects to load on this loop #}
                {% set content = dbt_artifacts.get_table_content_values(dataset, objects[i: i + upload_limit]) %}

                {# Insert the content into the metadata table #}
                {{ dbt_artifacts.insert_into_metadata_table(
                    dataset=dataset,
                    fields=dbt_artifacts.get_column_name_list(dataset),
                    content=content
                    )
                }}

            {# Loop the next 'chunk' #}
            {% endfor %}

        {# Loop the next 'dataset' #}
        {% endfor %}

    {% endif %}

{%- endmacro %}
