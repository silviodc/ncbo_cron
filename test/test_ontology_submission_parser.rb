require_relative 'test_case'
require 'json'
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
    @@ontologies = LinkedData::SampleData::Ontology.sample_owl_ontologies
  end

  def self.after_suite
    LinkedData::SampleData::Ontology.delete_ontologies_and_submissions
  end




  def test_queue_submission
    parser = NcboCron::Models::OntologySubmissionParser.new
    parser.queue_submission(@@ontologies[0].submissions[0], ["all", "index"])


    val = @@redis.hget(NcboCron::Models::OntologySubmissionParser::QUEUE_HOLDER, parser.get_prefixed_id(@@ontologies[0].submissions[0].id.to_s))
    puts  "#{@@ontologies[0].submissions[0].id.to_s} #{val}"

  end

  def test_parse_submissions
    parser = NcboCron::Models::OntologySubmissionParser.new
    parser.queue_submission(@@ontologies[0].submissions[0], actions=[:metrics, :index])
    parser.parse_submissions

  end



end