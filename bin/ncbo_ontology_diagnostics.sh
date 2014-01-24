#!/bin/bash

# 1) Ontologies without metrics.
# 2) Ontologies with no classes and/or ERROR_RDF in status.
# 3) Ontologies with no classes indexed in SOLR
# 4) Ontologies that are not in the annotator cache.


echo "Inspecting submissionStatus and metrics for all ontologies."
ncbo_ontology_inspector -p submissionStatus,metrics > logs/submission_status.log

# Filter the output log to remove summaryOnly ontologies.
grep -v 'summaryOnly' logs/submission_status.log > logs/submission_status_notSummaryOnly.log

echo
echo "Ontologies failing to parse, without RDF data:"
grep 'ERROR_RDF' logs/submission_status_notSummaryOnly.log

echo
echo "Ontologies with RDF data, without metrics:"
grep -v 'ERROR_RDF' logs/submission_status_notSummaryOnly.log | grep -v 'METRICS'

echo
echo "Ontologies with RDF data, without SOLR data:"
grep -v 'ERROR_RDF' logs/submission_status_notSummaryOnly.log | grep -v 'METRICS'

