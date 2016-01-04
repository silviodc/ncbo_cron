# NCBO CRON

A project with CRON job for the NCBO BioPortal

- Process or delete ontology
- Generate annotator dictionary and cache
- Calculate metrics
- Process mapping counts
- Bulk load mappings 


## Run manually

### Process an ontology
bin/ncbo_ontology_process -o STY

### Mappings bulk load 
To load a lot of mappings without using the REST API (which can take a long time)

- Put the mappings detailed in JSON in a file. Example (the first mapping have the minimum required informations):
```javascript
[
    { 
        "creator":"admin",
        "relation" : ["http://www.w3.org/2004/02/skos/core#exactMatch"],
        "classes" : {   "http://class_id1/id1" : "ONT_ACRONYM1",
                        "http://class_id2/id2" : "ONT_ACRONYM2"}
    },
    { 
        "creator":"admin",
        "source_contact_info":"admin@my_bioportal.org",
        "relation" : ["http://www.w3.org/2004/02/skos/core#exactMatch", "http://purl.org/linguistics/gold/freeTranslation"],
        "Source":"REST",
        "source_name":"Reconciliation of multilingual mapping",
        "comment" : "Interportal mapping with all possible informations (to the NCBO bioportal)",
        "classes" : {   "http://purl.lirmm.fr/ontology/STY/T071" : "STY",
                        "http://purl.bioontology.org/ontology/STY/T071" : "ncbo:STY"}
    }
]
```

- Run the job

bin/ncbo_mappings_bulk_load -b /path/to/mapping/file.json -l /path/to/log/file.log