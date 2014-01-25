#!/bin/bash

# 1) Ontologies without metrics.
# 2) Ontologies with no classes and/or ERROR_RDF in status.
# 3) Ontologies with no classes indexed in SOLR
# 4) Ontologies that are not in the annotator cache.


echo "Inspecting submissionStatus and metrics for all ontologies."
./bin/ncbo_ontology_inspector -p submissionStatus,metrics > logs/submission_status.log

# Filter the output log to remove summaryOnly ontologies.
grep -v -F 'summaryOnly' logs/submission_status.log > logs/submission_status_notSummaryOnly.log

echo
echo "Ontologies failing to parse, without RDF data:"
grep -F 'ERROR_RDF' logs/submission_status_notSummaryOnly.log

# Filter the output log to remove RDF errors from the ontologies with submissions.
grep -v -F 'ERROR_RDF' logs/submission_status_notSummaryOnly.log > logs/submission_status_withRDF.log

echo
echo "Ontologies with RDF data, without METRICS:"
grep -v -F 'METRICS' logs/submission_status_withRDF.log

echo
echo "Ontologies with RDF data, without SOLR data:"
grep -F 'INDEXCOUNT:0' logs/submission_status_withRDF.log
grep -F 'INDEXCOUNT_MISSING' logs/submission_status_withRDF.log
grep -F 'INDEXCOUNT_ERROR' logs/submission_status_withRDF.log

echo
echo "Ontologies with RDF data, without ANNOTATOR data:"
grep -F 'ANNOTATOR_MISSING' logs/submission_status_withRDF.log
grep -F 'ANNOTATOR_ERROR' logs/submission_status_withRDF.log
