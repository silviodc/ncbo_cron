# NCBO CRON

A project with CRON job for the NCBO BioPortal

- ncbo_cron daemon
- Process or delete ontology
- Generate annotator dictionary and cache
- Calculate metrics
- Process mapping counts
- Bulk load mappings 

## Run the ncbo_cron daemon

To run it use the `bin/ncbo_cron` command

Running this command without option will run the job according to the settings defined in the NcboCron config file. Or by default in [ncbo_cron/lib/ncbo_cron/config.rb](https://github.com/ncbo/ncbo_cron/blob/master/lib/ncbo_cron/config.rb)

But the user can add arguments to change some settings.

Here an example to run the flush old graph job every 3 hours and to disable the automatic pull of new submissions:

```
bin/ncbo_cron --flush-old-graphs "0 */3 * * *" --disable-pull
```

It will run by default as a daemon

But it will not run as a daemon if you use one of the following options:

* console (to open a pry console)
* view_queue (view the queue of jobs waiting for processing)
* queue_submission (adding a submission to the processing submission queue)
* kill (stop the ncbo_cron daemon)


## Stop the ncbo_cron daemon

The PID of the ncbo_cron process is in /var/run/ncbo_cron/ncbo_cron.pid

To stop the ncbo_cron daemon: 
```
bin/ncbo_cron -k
```


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



