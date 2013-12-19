#!/bin/bash

# Log all the ontology submission upload file paths, annotated with ERROR or VALID tags:
bundle exec ./bin/ncbo_submission_filepath_corrections -a -n > uploadFilePaths.log

# Find all the ontology submissions that have a submission in the correct uploadFilePath repository:
sed -e '/^VALID/!d' uploadFilePaths.log | cut -f2 | sed s/:// | uniq > uploadFilePathValidOntologies.txt
#sed -e 'N; /ERROR:\t\(.*\):.*submission:.*\nVALID:\t\1/!d' uploadFilePaths.log > uploadFilePathCorrectLatestSubmission.txt

