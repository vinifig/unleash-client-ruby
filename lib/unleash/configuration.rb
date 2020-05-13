require 'securerandom'
require 'tmpdir'

module Unleash
  class Configuration
    attr_accessor \
      :url,
      :app_name,
      :environment,
      :instance_id,
      :custom_http_headers,
      :disable_client,
      :disable_metrics,
      :timeout,
      :retry_limit,
      :refresh_interval,
      :metrics_interval,
      :backup_file,
      :logger,
      :log_level,
      :custom_strategies

    def initialize(opts = {})
      ensure_valid_opts(opts)
      set_defaults

      initialize_default_logger if opts[:logger].nil?

      merge(opts)
      refresh_backup_file!
    end

    def metrics_interval_in_millis
      self.metrics_interval * 1_000
    end

    def validate!
      return if self.disable_client

      raise ArgumentError, "URL and app_name are required parameters." if self.app_name.nil? || self.url.nil?
      raise ArgumentError, "custom_http_headers must be a hash." unless self.custom_http_headers.is_a?(Hash)
      raise ArgumentError, "custom_strategies must be an array." unless self.custom_strategies.is_a?(Array)
    end

    def refresh_backup_file!
      self.backup_file = Dir.tmpdir + "/unleash-#{app_name}-repo.json" if self.backup_file.nil?
    end

    def http_headers
      {
        'UNLEASH-INSTANCEID' => self.instance_id,
        'UNLEASH-APPNAME' => self.app_name
      }.merge(custom_http_headers.dup)
    end

    def fetch_toggles_url
      self.url + '/client/features'
    end

    def client_metrics_url
      self.url + '/client/metrics'
    end

    def client_register_url
      self.url + '/client/register'
    end

    # dynamically configured, should be cached!
    def strategies
      puts STRATEGIES
      puts "Unleash.configuration.custom_strategies: #{Unleash.configuration.custom_strategies}"

      cstats = Unleash.configuration.custom_strategies
        .flatten
        .compact
        .map do |klass|
          class_name_downcased = downcase_class_name(klass)
          [class_name_downcased.to_sym, klass.new]
        end
        .to_h

        # .map do |c|
        #   puts "c: #{c}"
        #   lowered_c = c.name.tap{ |c| c[0] = c[0].downcase }
        #   lowered_c[0] = lowered_c[0].downcase
        #   [lowered_c.to_sym, c.new]
        # end
        # .to_h

        puts cstats
        STRATEGIES.merge!(cstats)
    end

    private

    # attr_accessor :strategies

    def downcase_class_name(klass)
      klass.name.map do |c|
        c
        .each_with_index
        .map{ |c, i| (i == 0) ? c.downcase : c }
        .join("")
      end
    end

    def ensure_valid_opts(opts)
      unless opts[:custom_http_headers].is_a?(Hash) || opts[:custom_http_headers].nil?
        raise ArgumentError, "custom_http_headers must be a hash."
      end

      unless opts[:custom_strategies].is_a?(Array) && opts[:custom_strategies].each { |k| k&.method_defined? 'is_enabled?' } || opts[:custom_strategies].nil?
        puts "a: #{opts[:custom_strategies]}"
        raise ArgumentError, "custom_strategies must be an Arry of classes that respond to is_enabled? method."
      end
    end

    def set_defaults
      self.app_name         = nil
      self.environment      = 'default'
      self.url              = nil
      self.instance_id      = SecureRandom.uuid
      self.disable_client   = false
      self.disable_metrics  = false
      self.refresh_interval = 15
      self.metrics_interval = 10
      self.timeout          = 30
      self.retry_limit      = 1
      self.backup_file      = nil
      self.log_level        = Logger::WARN

      self.custom_http_headers = {}
      self.custom_strategies   = []
    end

    def initialize_default_logger
      self.logger = Logger.new(STDOUT)

      # on default logger, use custom formatter that includes thread_name:
      self.logger.formatter = proc do |severity, datetime, _progname, msg|
        thread_name = (Thread.current[:name] || "Unleash").rjust(16, ' ')
        "[#{datetime.iso8601(6)} #{thread_name} #{severity.ljust(5, ' ')}] : #{msg}\n"
      end
    end

    def merge(opts)
      opts.each_pair{ |opt, val| set_option(opt, val) }
      self
    end

    def set_option(opt, val)
      __send__("#{opt}=", val)
    rescue NoMethodError
      raise ArgumentError, "unknown configuration parameter '#{val}'"
    end
  end
end
