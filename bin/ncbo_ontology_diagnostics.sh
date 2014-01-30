#!/bin/bash

# 1) Ontologies without metrics.
# 2) Ontologies with no classes and/or ERROR_RDF in status.
# 3) Ontologies with no classes indexed in SOLR
# 4) Ontologies that are not in the annotator cache.


REFORMAT_LINES='s/;;/\n\t/g'


echo "Inspecting submissionStatus and metrics for all ontologies."
./bin/ncbo_ontology_inspector -p submissionStatus,metrics > logs/submission_status.log

echo
echo '*********************************************************************************************'
echo 'System config:'
CONFIG_PATTERN='(.*) >> Using'
grep -E $CONFIG_PATTERN logs/submission_status.log
grep -v -E $CONFIG_PATTERN logs/submission_status.log > logs/tmp.log
mv logs/tmp.log logs/submission_status.log

echo
echo '*********************************************************************************************'
echo 'Filtering log to remove summaryOnly ontologies.'
echo
grep -v -F 'summaryOnly' logs/submission_status.log > logs/tmp.log
sed -e 's/ontology=found;;//' logs/tmp.log > logs/submission_status_notSummaryOnly.log

echo
echo '*********************************************************************************************'
echo 'Ontologies missing a latest submission:'
echo
grep -F 'submissionId=ERROR' logs/submission_status_notSummaryOnly.log | sed -e $REFORMAT_LINES
# cleanup the submission log
grep -v -F 'submissionId=ERROR' logs/submission_status_notSummaryOnly.log > logs/submission_status_hasSubmission.log

echo
echo '*********************************************************************************************'
echo "Ontologies failing to parse, without RDF data ('ERROR_RDF','ERROR_RDF_LABELS'):"
echo
grep -F 'ERROR_RDF' logs/submission_status_hasSubmission.log | sed -e $REFORMAT_LINES
# Filter the output log to remove RDF errors from the ontologies with submissions.
grep -v -F 'ERROR_RDF' logs/submission_status_hasSubmission.log > logs/submission_status_withRDF.log

echo
echo '*********************************************************************************************'
echo 'Ontologies with RDF data, without METRICS:'
echo
grep -v -F 'METRICS' logs/submission_status_withRDF.log | sed -e $REFORMAT_LINES
grep -F 'METRICS_MISSING' logs/submission_status_withRDF.log | sed -e $REFORMAT_LINES
grep -F 'classes:0' logs/submission_status_withRDF.log | sed -e $REFORMAT_LINES
grep -F 'maxDepth:0' logs/submission_status_withRDF.log | sed -e $REFORMAT_LINES

echo
echo '*********************************************************************************************'
echo "Ontologies with RDF data, without SOLR data:"
echo
grep -F 'INDEXCOUNT:0' logs/submission_status_withRDF.log | sed -e $REFORMAT_LINES
grep -F 'INDEXCOUNT_MISSING' logs/submission_status_withRDF.log | sed -e $REFORMAT_LINES
grep -F 'INDEXCOUNT_ERROR' logs/submission_status_withRDF.log | sed -e $REFORMAT_LINES

echo
echo '*********************************************************************************************'
echo "Ontologies with RDF data, without ANNOTATOR data:"
echo
grep -F 'ANNOTATOR_MISSING' logs/submission_status_withRDF.log | sed -e $REFORMAT_LINES
grep -F 'ANNOTATOR_ERROR' logs/submission_status_withRDF.log | sed -e $REFORMAT_LINES

