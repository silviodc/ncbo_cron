require 'logger'
require 'google/api_client'
require 'google/api_client/auth/installed_app'

module NcboCron
  module Models

    class OntologyAnalytics
      ONTOLOGY_ANALYTICS_REDIS_FIELD = "ontology_analytics"

      def initialize(logger)
        @logger = logger
      end

      def run
        redis = Redis.new(:host => NcboCron.settings.redis_host, :port => NcboCron.settings.redis_port)
        ontology_analytics = fetch_ontology_analytics
        redis.set(ONTOLOGY_ANALYTICS_REDIS_FIELD, Marshal.dump(ontology_analytics))
      end

      def fetch_ontology_analytics
        google_client = authenticate_google
        api_method = google_client.discovered_api('analytics', 'v3').data.ga.get
        aggregated_results = Hash.new
        start_year = Date.parse(NcboCron.settings.analytics_start_date).year || 2013
        ont_acronyms = LinkedData::Models::Ontology.where.include(:acronym).all.map {|o| o.acronym}
        # ont_acronyms = ["NCIT", "ONTOMA", "CMPO", "AEO", "SNOMEDCT"]

        ont_acronyms.each do |acronym|
          max_results = 10000
          num_results = 10000
          start_index = 1
          results = nil

          loop do
            results = google_client.execute(:api_method => api_method, :parameters => {
              'ids'         => NcboCron.settings.analytics_profile_id,
              'start-date'  => NcboCron.settings.analytics_start_date,
              'end-date'    => Date.today.to_s,
              'dimensions'  => 'ga:pagePath,ga:year,ga:month',
              'metrics'     => 'ga:pageviews',
              'filters'     => "ga:pagePath=~^/ontologies/#{acronym}*;#{NcboCron.settings.analytics_filter_str}",
              'start-index' => start_index,
              'max-results' => max_results
            })
            start_index += max_results
            num_results = results.data.rows.length
            @logger.info "Acronym: #{acronym}, Results: #{num_results}, Start Index: #{start_index}"
            @logger.flush

            results.data.rows.each do |row|
              if (aggregated_results.has_key?(acronym))
                # year
                if (aggregated_results[acronym].has_key?(row[1].to_i))
                  # month
                  if (aggregated_results[acronym][row[1].to_i].has_key?(row[2].to_i))
                    aggregated_results[acronym][row[1].to_i][row[2].to_i] += row[3].to_i
                  else
                    aggregated_results[acronym][row[1].to_i][row[2].to_i] = row[3].to_i
                  end
                else
                  aggregated_results[acronym][row[1].to_i] = Hash.new
                  aggregated_results[acronym][row[1].to_i][row[2].to_i] = row[3].to_i
                end
              else
                aggregated_results[acronym] = Hash.new
                aggregated_results[acronym][row[1].to_i] = Hash.new
                aggregated_results[acronym][row[1].to_i][row[2].to_i] = row[3].to_i
              end
            end

            if (num_results == 0 || num_results < max_results)
              # fill up non existent years
              (start_year..Date.today.year).each { |y| aggregated_results[acronym][y] = Hash.new unless aggregated_results[acronym].has_key?(y) }
              # fill up non existent months with zeros
              (1..12).each { |n| aggregated_results[acronym].values.each { |v| v[n] = 0 unless v.has_key?(n) } }
              break
            end
          end
        end

        @logger.info "Completed ontology analytics refresh..."
        @logger.flush

        aggregated_results
      end

      def authenticate_google
        client = Google::APIClient.new(
          :application_name => NcboCron.settings.analytics_app_name,
          :application_version => NcboCron.settings.analytics_app_version
        )
        key = Google::APIClient::KeyUtils.load_from_pkcs12(NcboCron.settings.analytics_path_to_key_file, 'notasecret')
        client.authorization = Signet::OAuth2::Client.new(
          :token_credential_uri => 'https://accounts.google.com/o/oauth2/token',
          :audience => 'https://accounts.google.com/o/oauth2/token',
          :scope => 'https://www.googleapis.com/auth/analytics.readonly',
          :issuer => NcboCron.settings.analytics_service_account_email_address,
          :signing_key => key
        )
        client.authorization.fetch_access_token!
        client
      end

    end
  end
end

# require 'ontologies_linked_data'
# require 'goo'
# require 'ncbo_cron'
# LinkedData.config do |config|
#   config.goo_host          = "localhost"
#   config.goo_port          = 8080
# end
# NcboCron.config do |config|
#   config.redis_host = "localhost"
#   config.redis_port = 6379
#
#   Google Analytics config
#   config.analytics_service_account_email_address = "123456789999-sikipho0wk8q0atflrmw62dj4kpwoj3c@developer.gserviceaccount.com"
#   config.analytics_path_to_key_file              = "config/bioportal-analytics.p12"
#   config.analytics_profile_id                    = "ga:1234567"
#   config.analytics_app_name                      = "BioPortal"
#   config.analytics_app_version                   = "1.0.0"
#   config.analytics_start_date                    = "2013-10-01"
#   config.analytics_filter_str                    = "ga:networkLocation!@stanford;ga:networkLocation!@amazon"
# end
#
# ontology_analytics_log_path = File.join("logs", "ontology-analytics.log")
# ontology_analytics_logger = Logger.new(ontology_analytics_log_path)
# NcboCron::Models::OntologyAnalytics.new(ontology_analytics_logger).run
# ./bin/ncbo_cron --disable-processing true --disable-pull true --disable-flush true --disable-warmq true --enable-ontology-analytics true --ontology-analytics '22 * * * *'