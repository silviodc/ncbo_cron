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
CONFIG_PATTERN="\'(.*) >> Using\'"
grep -E $CONFIG_PATTERN logs/submission_status.log
grep -v -E $CONFIG_PATTERN logs/submission_status.log > logs/tmp.log
mv logs/tmp.log logs/submission_status.log

echo
echo '*********************************************************************************************'
echo 'Filtering log to remove summaryOnly ontologies.'
echo
grep -v -F 'summaryOnly' logs/submission_status.log | sed -e 's/ontology=found;;//' > logs/submission_status_notSummaryOnly.log

SUBMISSION_ERROR_LOG='logs/submission_status_errorSubmission.log'
SUBMISSION_UPLOAD_LOG='logs/submission_status_hasSubmission.log'
SUBMISSION_RDF_LOG='logs/submission_status_hasRDF.log'
SUBMISSION_ERROR_RDF_LOG='logs/submission_status_errorRDF.log'
SUBMISSION_ERROR_METRICS_LOG='logs/submission_status_errorMetrics.log'
SUBMISSION_ERROR_INDEX_LOG='logs/submission_status_errorIndex.log'
SUBMISSION_ERROR_ANNOTATOR_LOG='logs/submission_status_errorAnnotator.log'

echo
echo '*********************************************************************************************'
echo 'Ontologies missing a latest submission:'
echo

grep -F 'submissionId=ERROR' logs/submission_status_notSummaryOnly.log > $SUBMISSION_ERROR_LOG
cat $SUBMISSION_ERROR_LOG | sed -e $REFORMAT_LINES
# cleanup the submission log
grep -v -F 'submissionId=ERROR' logs/submission_status_notSummaryOnly.log > $SUBMISSION_UPLOAD_LOG

echo
echo '*********************************************************************************************'
echo "Ontologies failing to parse, without RDF data ('ERROR_RDF','ERROR_RDF_LABELS'):"
echo
grep -F 'ERROR_RDF' $SUBMISSION_UPLOAD_LOG > $SUBMISSION_ERROR_RDF_LOG
cat  $SUBMISSION_ERROR_RDF_LOG | sed -e $REFORMAT_LINES
# Filter the output log to remove RDF errors from the ontologies with submissions.
grep -v -F 'ERROR_RDF' $SUBMISSION_UPLOAD_LOG > $SUBMISSION_RDF_LOG

echo
echo '*********************************************************************************************'
echo 'Ontologies with RDF data, without METRICS:'
echo
grep -v -F 'METRICS'      $SUBMISSION_RDF_LOG >  $SUBMISSION_ERROR_METRICS_LOG
grep -F 'METRICS_MISSING' $SUBMISSION_RDF_LOG >> $SUBMISSION_ERROR_METRICS_LOG
grep -F 'classes:0'       $SUBMISSION_RDF_LOG >> $SUBMISSION_ERROR_METRICS_LOG
grep -F 'maxDepth:0'      $SUBMISSION_RDF_LOG >> $SUBMISSION_ERROR_METRICS_LOG
cat $SUBMISSION_ERROR_METRICS_LOG | sort -u | sed -e $REFORMAT_LINES

echo
echo '*********************************************************************************************'
echo "Ontologies with RDF data, without SOLR data:"
echo
grep -F 'INDEXCOUNT:0'       $SUBMISSION_RDF_LOG >  $SUBMISSION_ERROR_INDEX_LOG
grep -F 'INDEXCOUNT_MISSING' $SUBMISSION_RDF_LOG >> $SUBMISSION_ERROR_INDEX_LOG
grep -F 'INDEXCOUNT_ERROR'   $SUBMISSION_RDF_LOG >> $SUBMISSION_ERROR_INDEX_LOG
cat $SUBMISSION_ERROR_INDEX_LOG | sort -u | sed -e $REFORMAT_LINES

echo
echo '*********************************************************************************************'
echo "Ontologies with RDF data, without ANNOTATOR data:"
echo
grep -F 'ANNOTATOR_MISSING' $SUBMISSION_RDF_LOG >  $SUBMISSION_ERROR_ANNOTATOR_LOG
grep -F 'ANNOTATOR_ERROR'   $SUBMISSION_RDF_LOG >> $SUBMISSION_ERROR_ANNOTATOR_LOG
cat $SUBMISSION_ERROR_ANNOTATOR_LOG | sort -u | sed -e $REFORMAT_LINES

