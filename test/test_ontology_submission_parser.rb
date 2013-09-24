require_relative 'test_case'
require 'json'
require 'multi_json'
require 'redis'

class TestOntologySubmission < TestCase

  def self.before_suite
    @@redis = Redis.new(:host => $QUEUE_REDIS_HOST, :port => $QUEUE_REDIS_PORT)
    db_size = @@redis.dbsize

    if db_size > 2000
      puts "This test cannot be run. You are probably pointing to the wrong redis backend. "
      return
    end

    @@redis.del NcboCron::Models::OntologySubmissionParser::QUEUE_HOLDER

    LinkedData::SampleData::Ontology.delete_ontologies_and_submissions
    @@ont_count, @@acronyms, @@ontologies = LinkedData::SampleData::Ontology.create_ontologies_and_submissions(ont_count: 2, submission_count: 1, process_submission: false)
  end

  def self.after_suite
    @@redis.del NcboCron::Models::OntologySubmissionParser::QUEUE_HOLDER
    LinkedData::SampleData::Ontology.delete_ontologies_and_submissions
  end

  def test_queue_submission
    parser = NcboCron::Models::OntologySubmissionParser.new

    o1 = @@ontologies[0]
    o1.bring(:submissions) if o1.bring?(:submissions)
    parser.queue_submission(o1.submissions[0], {dummy_action: true})
    val = @@redis.hget(NcboCron::Models::OntologySubmissionParser::QUEUE_HOLDER, parser.get_prefixed_id(o1.submissions[0].id.to_s))
    assert_nil val

    parser.queue_submission(o1.submissions[0], {
        dummy_action: true, index_search: false, metrics: true,
        process_annotator: true, another_dummy_action: true, all: true})
    val = @@redis.hget(NcboCron::Models::OntologySubmissionParser::QUEUE_HOLDER, parser.get_prefixed_id(o1.submissions[0].id.to_s))
    options = MultiJson.load(val, symbolize_keys: true)
    assert_equal NcboCron::Models::OntologySubmissionParser::ACTIONS, options

    o2 = @@ontologies[1]
    o2.bring(:submissions) if o2.bring?(:submissions)
    parser.queue_submission(o2.submissions[0], {
        :process_rdf => false, :index_search => true, :metrics => true,
        :process_annotator => false})
    val = @@redis.hget(NcboCron::Models::OntologySubmissionParser::QUEUE_HOLDER, parser.get_prefixed_id(o2.submissions[0].id.to_s))
    options = MultiJson.load(val, symbolize_keys: true)
    assert_equal({:process_rdf => false, :index_search => true, :process_annotator => false}, options)
  end

  def test_parse_submissions
    parser = NcboCron::Models::OntologySubmissionParser.new

    o1 = @@ontologies[0]
    o1.bring(:submissions) if o1.bring?(:submissions)
    sub1 = o1.submissions[0]
    sub1.bring(:submissionStatus) if sub1.bring?(:submissionStatus)

    o2 = @@ontologies[1]
    o2.bring(:submissions) if o2.bring?(:submissions)
    sub2 = o2.submissions[0]
    sub2.bring(:submissionStatus) if sub2.bring?(:submissionStatus)

    parser.queue_submission(sub1, {
        :dummy_action => true, :process_rdf => true, :index_search => true,
        :dummy_metrics => false, :run_metrics => false, :process_annotator => false,
        :another_dummy_action => false, :all => false})
    parser.queue_submission(sub2, {
        dummy_action: false, process_rdf: true, index_search: false,
        dummy_metrics: true, run_metrics: false, process_annotator: true,
        another_dummy_action: true, all: false})

    parser.process_queue_submissions

    sub1 = LinkedData::Models::OntologySubmission.find(RDF::IRI.new(sub1.id)).first
    sub1.bring(:submissionStatus) if sub1.bring?(:submissionStatus)
    sub2 = LinkedData::Models::OntologySubmission.find(RDF::IRI.new(sub2.id)).first
    sub2.bring(:submissionStatus) if sub2.bring?(:submissionStatus)
    sub1statusCodes = LinkedData::Models::SubmissionStatus.get_status_codes(sub1.submissionStatus)
    assert_equal [], ["UPLOADED", "RDF", "RDF_LABELS", "INDEXED"] - sub1statusCodes
    sub2statusCodes = LinkedData::Models::SubmissionStatus.get_status_codes(sub2.submissionStatus)
    assert_equal [], ["UPLOADED", "RDF", "RDF_LABELS", "ANNOTATOR"] - sub2statusCodes
  end

end