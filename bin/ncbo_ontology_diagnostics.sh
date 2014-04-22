#!/bin/bash

# 1) Ontologies without metrics.
# 2) Ontologies with no classes and/or ERROR_RDF in status.
# 3) Ontologies with no classes indexed in SOLR
# 4) Ontologies that are not in the annotator cache.


SED_ARG1="s/;;/\n\t/g"
SED_ARG2="s#acronym=#http://bioportal.bioontology.org/ontologies/#"

SUBMISSION_STATUS_LOG='logs/submission_status.log'
SUBMISSION_NOTSUMMARYONLY_LOG='logs/submission_status_notSummaryOnly.log'
SUBMISSION_ERROR_LOG='logs/submission_status_errorSubmission.log'
SUBMISSION_UPLOAD_LOG='logs/submission_status_hasSubmission.log'
SUBMISSION_RDF_LOG='logs/submission_status_hasRDF.log'
SUBMISSION_ERROR_RDF_LOG='logs/submission_status_errorRDF.log'
SUBMISSION_ERROR_METRICS_LOG='logs/submission_status_errorMetrics.log'
SUBMISSION_ERROR_MAXDEPTH_LOG='logs/submission_status_errorMaxDepth.log'
SUBMISSION_ERROR_INDEX_LOG='logs/submission_status_errorIndex.log'
SUBMISSION_ERROR_ANNOTATOR_LOG='logs/submission_status_errorAnnotator.log'
SUBMISSION_ERROR_TMP_LOG='logs/submission_status_errorTMP.log'

SUBMISSION_ERROR_FORMAT_LOG='logs/submission_status_errorSubmission_formatted.log'
SUBMISSION_UPLOAD_FORMAT_LOG='logs/submission_status_hasSubmission_formatted.log'
SUBMISSION_RDF_FORMAT_LOG='logs/submission_status_hasRDF_formatted.log'
SUBMISSION_ERROR_RDF_FORMAT_LOG='logs/submission_status_errorRDF_formatted.log'
SUBMISSION_ERROR_METRICS_FORMAT_LOG='logs/submission_status_errorMetrics_formatted.log'
SUBMISSION_ERROR_MAXDEPTH_FORMAT_LOG='logs/submission_status_errorMaxDepth_formatted.log'
SUBMISSION_ERROR_INDEX_FORMAT_LOG='logs/submission_status_errorIndex_formatted.log'
SUBMISSION_ERROR_ANNOTATOR_FORMAT_LOG='logs/submission_status_errorAnnotator_formatted.log'


echo "Running ncbo_ontology_inspector for all ontologies."
./bin/ncbo_ontology_inspector -p flat,hasOntologyLanguage,metrics,submissionStatus > $SUBMISSION_STATUS_LOG

echo
echo '*********************************************************************************************'
echo 'System config:'
grep -E '(.*) >> Using|ncbo-cube' $SUBMISSION_STATUS_LOG
grep -v -E '(.*) >> Using|ncbo-cube' $SUBMISSION_STATUS_LOG > logs/tmp.log
mv logs/tmp.log $SUBMISSION_STATUS_LOG

echo
echo '*********************************************************************************************'
echo 'Filtering log to remove summaryOnly ontologies.'
echo
grep -v -F 'summaryOnly' $SUBMISSION_STATUS_LOG | sed -e 's/ontology=found;;//' > $SUBMISSION_NOTSUMMARYONLY_LOG

echo
echo '*********************************************************************************************'
echo 'Ontologies missing a latest submission upload:'
echo

# grep -F 'submissionId=ERROR' $SUBMISSION_NOTSUMMARYONLY_LOG > $SUBMISSION_ERROR_LOG
grep -v -F 'UPLOADED' $SUBMISSION_NOTSUMMARYONLY_LOG > $SUBMISSION_ERROR_LOG
cat $SUBMISSION_ERROR_LOG | sed -e $SED_ARG1 -e $SED_ARG2 | grep -F 'http' | tee $SUBMISSION_ERROR_FORMAT_LOG
# cleanup the submission log
grep -F 'UPLOADED' $SUBMISSION_NOTSUMMARYONLY_LOG > $SUBMISSION_UPLOAD_LOG


#############################################################################################################
# The RDF processing requires a successful submission UPLOAD.

echo
echo '*********************************************************************************************'
echo "Ontologies failing to parse, without RDF data ('ERROR_RDF','ERROR_RDF_LABELS'):"
echo
grep -F 'ERROR_RDF' $SUBMISSION_UPLOAD_LOG > $SUBMISSION_ERROR_RDF_LOG
cat  $SUBMISSION_ERROR_RDF_LOG | sed -e $SED_ARG1 -e $SED_ARG2 | grep -v -F 'metrics=' | tee $SUBMISSION_ERROR_RDF_FORMAT_LOG
# Filter the output log to remove RDF errors from the ontologies with submissions.
grep -v -F 'ERROR_RDF' $SUBMISSION_UPLOAD_LOG | grep -F 'RDF' > $SUBMISSION_RDF_LOG

# INFO: Call ncbo_cron to reprocess the RDF failures once.
#./bin/ncbo_cron --add-submission {submission id to add to the queue}


echo
echo '*********************************************************************************************'
echo "Ontologies with RDF data, with no classes (may be an error, or by design):"
echo
grep -F 'classes:0'     $SUBMISSION_RDF_LOG | sed -e $SED_ARG1 -e $SED_ARG2
# Exclude entries without any classes, they cannot be indexed or used in the annotator.
grep -v -F 'classes:0'  $SUBMISSION_RDF_LOG > $SUBMISSION_ERROR_TMP_LOG


#############################################################################################################
# The metrics, SOLR index, and annotator all depend on successful RDF parsing.  Otherwise, they are
# independent processing operations.

echo
echo '*********************************************************************************************'
echo 'Ontologies with RDF data, without METRICS:'
echo
grep -v -F 'METRICS'      $SUBMISSION_ERROR_TMP_LOG >  $SUBMISSION_ERROR_METRICS_LOG
grep -F 'METRICS_MISSING' $SUBMISSION_ERROR_TMP_LOG >> $SUBMISSION_ERROR_METRICS_LOG
cat $SUBMISSION_ERROR_METRICS_LOG | sed -e $SED_ARG1 -e $SED_ARG2 | tee $SUBMISSION_ERROR_METRICS_FORMAT_LOG

echo '*********************************************************************************************'
echo 'Ontologies with RDF data and METRICS has maxDepth == 0 && classesWithOneChild != 0 :'
echo
grep -F 'maxDepth:0' $SUBMISSION_ERROR_TMP_LOG | grep -F -v 'classesWithOneChild:0' > $SUBMISSION_ERROR_MAXDEPTH_LOG
cat $SUBMISSION_ERROR_MAXDEPTH_LOG | sed -e $SED_ARG1 -e $SED_ARG2 | tee $SUBMISSION_ERROR_MAXDEPTH_FORMAT_LOG

# INFO: possible metrics fix:
# ./bin/ncbo_ontology_metrics -o {ONTOLOGY_ACRONYM}
# INFO: then check the output from
# ./bin/ncbo_ontology_inspector -p flat,metrics,submissionStatus -o {ONTOLOGY_ACRONYM}

echo
echo '*********************************************************************************************'
echo "Ontologies with RDF data, without SOLR data:"
echo
# grep -F 'INDEXCOUNT:0' $SUBMISSION_ERROR_TMP_LOG >  $SUBMISSION_ERROR_INDEX_LOG
grep -F 'INDEX_ERROR'  $SUBMISSION_ERROR_TMP_LOG > $SUBMISSION_ERROR_INDEX_LOG
cat $SUBMISSION_ERROR_INDEX_LOG | sed -e $SED_ARG1 -e $SED_ARG2 | tee $SUBMISSION_ERROR_INDEX_FORMAT_LOG

# INFO: possible SOLR index fix:
# ./bin/ncbo_ontology_index -o {ONTOLOGY_ACRONYM}

echo
echo '*********************************************************************************************'
echo "Ontologies with RDF data, without ANNOTATOR data:"
echo
grep -F 'ANNOTATIONS_UPDATING' $SUBMISSION_ERROR_TMP_LOG >  $SUBMISSION_ERROR_ANNOTATOR_LOG
grep -F 'ANNOTATIONS_MISSING'  $SUBMISSION_ERROR_TMP_LOG >> $SUBMISSION_ERROR_ANNOTATOR_LOG
grep -F 'ANNOTATIONS_ERROR'    $SUBMISSION_ERROR_TMP_LOG >> $SUBMISSION_ERROR_ANNOTATOR_LOG
cat $SUBMISSION_ERROR_ANNOTATOR_LOG | sed -e $SED_ARG1 -e $SED_ARG2 | tee $SUBMISSION_ERROR_ANNOTATOR_FORMAT_LOG

# INFO: possible SOLR index fix:
# ./bin/ncbo_ontology_annotate -o {ONTOLOGY_ACRONYM}

rm $SUBMISSION_ERROR_TMP_LOG 
