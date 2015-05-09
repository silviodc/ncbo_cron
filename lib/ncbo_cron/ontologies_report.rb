require 'logger'
require 'benchmark'

module NcboCron
  module Models
    class OntologiesReport

      ERROR_CODES = {
          summaryOnly:                              "Ontology is summary-only",
          flat:                                     "This ontology is designated as 'flat'",
          errSummaryOnlyWithSubmissions:            "Ontology has submissions but it is set to summary-only",
          errNoSubmissions:                         "Ontology has no submissions",
          errNoReadySubmission:                     "Ontology has no submissions in a ready state",
          errNoLatestReadySubmission:               lambda { |n| "The latest submission is not ready and is ahead of the latest ready by #{n} revision#{n > 1?'s':''}" },
          errNoClassesLatestReadySubmission:        "The latest ready submission has no classes",
          errNoRootsLatestReadySubmission:          "The latest ready submission has no roots",
          errNoMetricsLatestReadySubmission:        "The latest ready submission has no metrics",
          errIncorrectMetricsLatestReadySubmission: "The latest ready submission has incorrect metrics",
          errNoAnnotator:                           "Annotator returns no results for this ontology",
          errNoSearch:                              "Search returns no results for this ontology",
          errErrorStatus:                           [],
          errMissingStatus:                         []
      }

      def initialize(logger, saveto)
        @logger = logger
        @saveto = saveto
      end

      def run
        @logger.info("Running ontologies report...\n")
        ontologies = LinkedData::Models::Ontology.where.include(:acronym).all
        # ontologies_to_indclude = ["AERO", "SBO", "EHDAA", "CCO", "ONLIRA", "VT", "ZEA", "SMASH", "PLIO", "OGI", "CO", "NCIT", "GO"]
        # ontologies_to_indclude = ["DCM", "D1-CARBON-FLUX", "STUFF"]
        # ontologies.select! { |ont| ontologies_to_indclude.include?(ont.acronym) }
        report = {ontologies: {}, date_generated: nil}
        count = 0
        ontologies.each do |ont|
          count += 1
          @logger.info("Processing report for #{ont.acronym} - #{count} of #{ontologies.length} ontologies."); @logger.flush
          time = Benchmark.realtime do
            report[:ontologies][ont.acronym] = sanity_report(ont)
          end
          @logger.info("Finished report for #{ont.acronym} in #{time} sec."); @logger.flush
        end

        tm = Time.new
        report[:date_generated] = tm.strftime("%m/%d/%Y %I:%M%p")
        File.open(@saveto, 'w') { |file| file.write(JSON.pretty_generate(report)) }
        @logger.info("Finished generating ontologies report. Wrote report data to #{@saveto}.\n"); @logger.flush
      end

      def sanity_report(ont)
        report = {problem: false}
        ont.bring_remaining()
        ont.bring(:submissions)
        submissions = ont.submissions

        # first see if is summary only and if it has submissions
        if ont.summaryOnly
          if !submissions.nil? && submissions.length > 0
            add_error_code(report, :errSummaryOnlyWithSubmissions)
          else
            add_error_code(report, :summaryOnly)
          end
          return report
        end

        # check if latest submission is the one ready
        latest_any = ont.latest_submission(status: :any)
        if latest_any.nil?
          # no submissions, cannot continue
          add_error_code(report, :errNoSubmissions)
          return report
        end

        latest_ready = ont.latest_submission
        if latest_ready.nil?
          # no ready submission exists, cannot continue
          add_error_code(report, :errNoReadySubmission)
          # add error statuses from the latest non-ready submission
          latest_any.submissionStatus.each { |st| add_error_code(report, :errErrorStatus, st.get_code_from_id) if st.error? }
          return report
        end

        # submission that's ready is not the latest one
        if latest_any.id.to_s != latest_ready.id.to_s
          sub_count = 0
          latest_submission_id = latest_ready.submissionId.to_i
          ont.submissions.each { |sub| sub_count += 1 if sub.submissionId.to_i > latest_submission_id }
          add_error_code(report, :errNoLatestReadySubmission, sub_count)
        end

        # rest of the tests run for latest_ready
        sub = latest_ready
        sub.bring_remaining()
        sub.ontology.bring_remaining()
        sub.bring(:metrics)

        # add error statuses
        sub.submissionStatus.each { |st| add_error_code(report, :errErrorStatus, st.get_code_from_id) if st.error? }

        # add missing statuses
        statuses = LinkedData::Models::SubmissionStatus.where.all
        statuses.select! { |st| !st.error? }
        statuses.select! { |st| st.id.to_s["DIFF"].nil? }
        statuses.select! { |st| st.id.to_s["ARCHIVED"].nil? }
        statuses.select! { |st| st.id.to_s["RDF_LABELS"].nil? }

        statuses.each do |ok|
          found = false
          sub.submissionStatus.each do |st|
            if st == ok
              found = true
              break
            end
          end
          add_error_code(report, :errMissingStatus, ok.get_code_from_id) unless found
        end

        # check whether ontology has been designated as "flat" or root classes exist
        if sub.ontology.flat
          add_error_code(report, :flat)
        else
          add_error_code(report, :errNoRootsLatestSubmission) unless sub.roots().length > 0
        end

        # check if metrics has been generated
        metrics = sub.metrics
        if metrics.nil?
          add_error_code(report, :errNoMetricsLatestSubmission)
        else
          metrics.bring_remaining()
          if metrics.classes + metrics.properties < 10
            add_error_code(report, :errIncorrectMetricsLatestSubmission)
          end
        end

        # check if classes exist
        good_classes = good_classes(sub)

        if good_classes.empty?
          add_error_code(report, :errNoClassesLatestSubmission)
        else
          search_text = good_classes.join(" , ")
          # check for Annotator calls
          ann = Annotator::Models::NcboAnnotator.new(@logger)
          ann_response = ann.annotate(search_text, { ontologies: [ont.acronym] })
          add_error_code(report, :errNoAnnotator) if ann_response.length < good_classes.length

          # check for Search calls
          resp = LinkedData::Models::Class.search(solr_escape(search_text), query_params(ont.acronym))
          add_error_code(report, :errNoSearch) if resp["response"]["numFound"] < good_classes.length
        end

        return report
      end

      def good_classes(submission)
        page = 1
        size = 10
        paging = LinkedData::Models::Class.in(submission).include(:prefLabel, :synonym).page(page, size)
        good_classes = Array.new

        begin
          page_classes = paging.all
          break if page_classes.empty?

          page_classes.each do |cls|
            prefLabel = nil

            begin
              prefLabel = cls.prefLabel
            rescue Goo::Base::AttributeNotLoaded =>  e
              next
            end

            # Skip classes with no prefLabel or b-nodes
            next if prefLabel.nil? || cls.id.to_s.include?(".well-known/genid")

            # store good prefLabel
            good_classes << prefLabel
            break if good_classes.length === size
          end

          break if good_classes.length === size
          page = page_classes.next_page

          if page
            paging.page(page)
          end
        end while !page.nil?

        good_classes
      end

      def solr_escape(text)
        RSolr.solr_escape(text).gsub(/\s+/,"\\ ")
      end

      def add_error_code(report, code, data=nil)
        report[:problem] = false unless report.has_key? :problem
        if ERROR_CODES.has_key? code
          if ERROR_CODES[code].kind_of?(Array)
            unless data.nil?
              report[code] = [] unless report.has_key? code
              report[code] << data
            end
          elsif ERROR_CODES[code].is_a? (Proc)
            unless data.nil?
              report[code] = ERROR_CODES[code].call(data)
            end
          else
            report[code] = ERROR_CODES[code]
          end
          report[:problem] = true if code.to_s.start_with? "err"
        end
      end

      def query_params(acronym)
        return {
          "defType" => "edismax",
          "stopwords" => "true",
          "lowercaseOperators" => "true",
          "fl" => "*,score",
          "hl" => "on",
          "hl.simple.pre" => "<em>",
          "hl.simple.post" => "</em>",
          "qf" => "resource_id^100 prefLabelExact^90 prefLabel^70 synonymExact^50 synonym^10 notation cui semanticType",
          "hl.fl" => "resource_id prefLabelExact prefLabel synonymExact synonym notation cui semanticType",
          "fq" => "submissionAcronym:\"#{acronym}\" AND obsolete:false",
          "page" => 1,
          "pagesize" => 50,
          "start" => 0,
          "rows" => 50
        }
      end

    end
  end
end

# require 'ontologies_linked_data'
# require 'goo'
# require 'ncbo_annotator'
# require 'ncbo_cron/config'
# require_relative '../../config/config'
#
# ontologies_report_path = File.join("logs", "ontologies-report.log")
# ontologies_report_logger = Logger.new(ontologies_report_path)
# save_report_path = "../test/reports/ontologies_report.json"
# NcboCron::Models::OntologiesReport.new(ontologies_report_logger, save_report_path).run
# ./bin/ncbo_cron --disable-processing true --disable-pull true --disable-flush true --disable-warmq true --disable-ontology-analytics true --ontologies-report '22 * * * *'