require 'redis'
require 'ontologies_linked_data'
require 'ncbo_annotator'
require_relative '../../../config/config'
require_relative '../ontology_submission_parser'

def get_obo_submissions
  subs = []
  LinkedData::Models::Ontology.where.include(:acronym, :summaryOnly).all.each do |ont|
    if !ont.summaryOnly
      sub = ont.latest_submission(status: :any)
      if sub
        sub.bring(:hasOntologyLanguage)
        if sub.hasOntologyLanguage.obo?
          subs << sub
        end
      else
        puts "OBO ontology with no submissions #{ont.id.to_s}"
      end
    end
  end
  return subs
end

submission_queue = NcboCron::Models::OntologySubmissionParser.new

submissions = get_obo_submissions
submissions.each do |s|
  submission_queue.queue_submission(s, {all: true})
end
puts "Added #{submissions.length} to the queue."
