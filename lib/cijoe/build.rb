require 'yaml'

class CIJoe
  class Build < Struct.new(:user, :project, :started_at, :finished_at, :sha, :status, :output, :pid, :total, :passes, :fails, :faillog)
    def initialize(*args)
      super
      self.started_at ||= Time.now
    end

    def status
      return super if started_at && finished_at
      :building
    end

    def failed?
      status == :failed
    end

    def worked?
      status == :worked
    end

    def short_sha
      if sha
        sha[0,7]
      else
        "<unknown>"
      end
    end

    def clean_output
      output.gsub(/\e\[.+?m/, '').strip
    end

    def commit
      return if sha.nil?
      @commit ||= Commit.new(sha, user, project)
    end

    def dump(file)
      config = [user, project, started_at, finished_at, sha, status, output, pid, total, passes, fails, faillog]
      data = YAML.dump(config)
      File.open(file, 'wb') { |io| io.write(data) }
    end

    def self.load(file)
      if File.exist?(file)
        config = YAML.load(File.read(file))

        if config[8].to_s == "" or config[9].to_s == "" or config[10].to_s == ""
          config[8] = $1 if config[6] =~ /Total: ([0-9]+)/
          config[9] = $1 if config[6] =~ /Passed: ([0-9]+)/
          config[10] = $1 if config[6] =~ /Failed: ([0-9]+)/
        end
        
        new *config
      end
    end
  end
end
