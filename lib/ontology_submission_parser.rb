require 'redis'
require 'ontologies_linked_data'


module OntologySubmission
  module Models

    class OntologySubmissionParser

      QUEUE_HOLDER = "parseQueue"
      TASK_DELIM = "|"
      LABEL_DELIM = ","

      def initialize()
      end

    end
  end
end
