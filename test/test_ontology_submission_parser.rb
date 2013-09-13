require_relative 'test_case'
require 'json'
require 'multi_json'
require 'redis'

class TestCron < TestCase

  def self.before_suite
    @@redis = Redis.new(:host => LinkedData.settings.redis_host, :port => LinkedData.settings.redis_port)
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
    o2 = @@ontologies[1]
    o2.bring(:submissions) if o2.bring?(:submissions)
    parser.queue_submission(o1.submissions[0], {
        :dummy_action => true, :index_search => true, :metrics => false,
        :process_annotator => true, :another_dummy_action => false, :all => false})
    parser.queue_submission(o2.submissions[0], {
        dummy_action: false, index_search: false, metrics: true,
        process_annotator: true, another_dummy_action: true, all: false})
    parser.process_queue_submissions




  end



end