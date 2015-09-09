
module NCBOCron
  module Models
  
    class MappingCounts
      def initialize(logger)
        @logger = logger
      end
  
      def run
        LinkedData::Mappings.create_mapping_counts(@logger)
      end
    end
  
  end
end