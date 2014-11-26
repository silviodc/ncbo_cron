module NcboCron
  module Models
    class OntologiesReport
      def initialize(logger,saveto)
        @logger = logger
        @saveto = saveto
      end

      def run
        @logger.info("running report...\n")
        ontologies = LinkedData::Models::Ontology.where.include(:acronym).all
        report = {}
        count = 0
        ontologies.each do |ont|
          count += 1
          @logger.info(" #{count}/#{ontologies.length} ontology #{ont.acronym} ... ")
          @logger.flush()
          report[ont.acronym] = sanity_report(ont)
          @logger.info("DONE")
        end

        File.open(@saveto, 'w') { |file| file.write(JSON.pretty_generate(report)) }
      end

      def sanity_report(ont)
        report = {}
        ont.bring_remaining()
        ont.bring(:submissions)
        submissions = ont.submissions

        #first see if is summary only and if it has submissions
        if ont.summaryOnly
          if !submissions.nil? && submissions.length > 0
            report[:summaryOnly] = :ko_summary_only_with_submissions
          else
            report[:summaryOnly] = :ok
          end
          return report
        end

        #check if latest submission is the one ready
        latest_any = ont.latest_submission(status: :any)
        if latest_any.nil?
          report[:hasSubmissions] = :ko
          #no submissions then the other tests cannot run
          return report
        end
        report[:hasSubmissions] = :ok
        latest_ready = ont.latest_submission
        if latest_ready.nil?
          report[:hasReadySubmission] = :ko
          return report
        end
        report[:hasReadySubmission] = :ok
        if latest_any.id.to_s != latest_ready.id.to_s
          report[:latestSubmissionIsReady] = :ko
        else
          report[:latestSubmissionIsReady] = :ok
        end

        #rest of the tests run for latest_ready
        sub = latest_ready

        sub.bring_remaining()
        sub.ontology.bring_remaining()
        sub.bring(:metrics)

        statuses = LinkedData::Models::SubmissionStatus.where.all
        statuses.select! { |st| !st.error? }
        statuses.select! { |st| st.id.to_s["DIFF"].nil? }
        statuses.select! { |st| st.id.to_s["ARCHIVED"].nil? }
        statuses.select! { |st| st.id.to_s["RDF_LABELS"].nil? }

        report[:error_status] = []
        sub.submissionStatus.each do |st|
          if st.error?
            report[:error_status] << st.id.to_s.split("/")[-1]
          end
        end

        report[:missing_status] = []
        statuses.each do |ok|
          found = false
          sub.submissionStatus.each do |st|
            if st == ok
              found = true
              break
            end
          end
          if !found
            report[:missing_status] << ok.id.to_s.split("/")[-1]
          end
        end

        #classes, roots
        first_page_classes = LinkedData::Models::Class.in(sub)
                              .include(:prefLabel, :synonym).page(1,10).all
        if first_page_classes.length == 0 
          report[:classes] = :panic
        else
          report[:classes] = :ok
        end


        if sub.ontology.flat
          report[:roots] = :na
        else
          if sub.roots().length > 0
            report[:roots] = :ok
          else
            report[:roots] = :ko
          end
        end

        report[:metrics] = []
        metrics = sub.metrics
        if metrics.nil?
          report[:metrics] << :object_ko
        else
          metrics.bring_remaining()
          if metrics.classes + metrics.properties < 10
            report[:metrics] = :data_ko
          else
            report[:metrics] << :data_ok
          end
        end
        if first_page_classes.length > 0
          text_ann = first_page_classes.map { |c| c.prefLabel }.join(" | ")
          ann = Annotator::Models::NcboAnnotator.new(@logger)
          ann_response = ann.annotate(text_ann,
                                      { ontologies: [ ont.acronym ] })
          if ann_response.length > 10
            report[:annotator] = :ok
          else
            report[:annotator] = :ko
          end

          search_query = first_page_classes.first.prefLabel
          resp = LinkedData::Models::Class.search(
                    search_query,query_params(ont.acronym))
          if resp["response"]["numFound"] > 0
            report[:search] = :ok
          else
            report[:search] = :ko
          end
        end
        return report
      end
      def query_params(acronym)
        return {"defType"=>"edismax",
         "stopwords"=>"true",
         "lowercaseOperators"=>"true",
         "fl"=>"*,score",
         "hl"=>"on",
         "hl.simple.pre"=>"<em>",
         "hl.simple.post"=>"</em>",
         "qf"=>
          "resource_id^100 prefLabelExact^90 prefLabel^70 synonymExact^50 synonym^10 notation cui semanticType",
         "hl.fl"=>
          "resource_id prefLabelExact prefLabel synonymExact synonym notation cui semanticType",
         "fq"=>"submissionAcronym:\"#{acronym}\" AND obsolete:false",
         "page"=>1,
         "pagesize"=>50,
         "start"=>0,
         "rows"=>50}
      end

    end
  end
end
