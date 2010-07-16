##
# CI Joe.
# Because knowing is half the battle.
#
# This is a stupid simple CI server. It can build one (1)
# git-based project only.
#
# It only remembers the last build.
#
# It only notifies to Campfire.
#
# It's a RAH (Real American Hero).
#
# Seriously, I'm gonna be nuts about keeping this simple.

begin
  require 'systemu'
rescue LoadError
  abort "** Please install systemu"
end

require 'cijoe/version'
require 'cijoe/config'
require 'cijoe/commit'
require 'cijoe/build'
require 'cijoe/email'
require 'cijoe/server'

class CIJoe
  attr_reader :user, :project, :url, :current_build, :old_builds

  def initialize(project_path)
    project_path = File.expand_path(project_path)
    Dir.chdir(project_path)

    @user, @project = git_user_and_project
    @url = "http://github.com/#{@user}/#{@project}"

    @old_builds = []
    @current_build = nil

    trap("INT") { stop }
  end

  # is a build running?
  def building?
    !!@current_build
  end

  # the pid of the running child process
  def pid
    building? and current_build.pid
  end

  # kill the child and exit
  def stop
    Process.kill(9, pid) if pid
    exit!
  end

  # build callbacks
  def build_failed(output, error)
    finish_build :failed, "#{error}\n\n#{output}"
    run_hook "build-failed"
  end

  def build_worked(output)
    finish_build :worked, output
    run_hook "build-worked"
  end

  def finish_build(status, output)
    @current_build.finished_at = Time.now
    @current_build.status = status
    @current_build.output = output

    @current_build.total = $1 if output =~ /Agg Total: ([0-9]+)/
    @current_build.passes = $1 if output =~ /Agg Passed: ([0-9]+)/
    @current_build.fails = $1 if output =~ /Agg Failed: ([0-9]+)/

    Dir.glob("**/*.txt") do |f|
      @current_build.faillog = IO.read(f) if f =~ /faillog/
    end

    @old_builds.insert(0,@current_build)

    @current_build = nil
    write_build 'current', @current_build

    @old_builds.each do |build|

      name = build.finished_at.to_i.to_s
      write_build name,build unless File.exist? ".git/builds/#{name}"

    end
    clean_builds

    # Send email notifications if this build failed, or this build
    # worked after the last one failed
    if @old_builds[0].failed?
      @old_builds[0].notify_fail
    end

    if @old_builds[0].worked? && @old_builds[1].failed?
      @old_builds[0].notify_recover
    end

  end

  # run the build but make sure only
  # one is running at a time
  def build
    return if building?
    @current_build = Build.new(@user, @project)
    write_build 'current', @current_build
    Thread.new { build! }
  end

  def open_pipe(cmd)
    read, write = IO.pipe

    pid = fork do
      read.close
      STDOUT.reopen write
      exec cmd
    end

    write.close

    yield read, pid
  end

  # update git then run the build
  def build!
    build = @current_build
    output = ''
    git_update
    build.sha = git_sha
    write_build 'current', build

    status, stdout, stderr = systemu(runner_command) do |pid|
      build.pid = pid
      write_build 'current', build  
    end
    err, out = stderr, stdout
    status.exitstatus.to_i == 0 ? build_worked(out) : build_failed(out, err)
  rescue Object => e
    puts "Exception building: #{e.message} (#{e.class})"
    build_failed('', e.to_s)
  end

  # shellin' out
  def runner_command
    runner = Config.cijoe.runner.to_s
    runner == '' ? "rake -s test:units" : runner
  end

  def git_sha
    `git rev-parse origin/#{git_branch}`.chomp
  end

  def git_update
    `git fetch origin && git reset --hard origin/#{git_branch}`
    run_hook "after-reset"
  end

  def git_user_and_project
    Config.remote.origin.url.to_s.chomp('.git').split(':')[-1].split('/')[-2, 2]
  end

  def git_branch
    branch = Config.cijoe.branch.to_s
    branch == '' ? "master" : branch
  end

  # massage our repo
  def run_hook(hook)
    if File.exists?(file=".git/hooks/#{hook}") && File.executable?(file)
      data =
        if @old_builds[0] && @old_builds[0].commit
          {
            "MESSAGE" => @old_builds[0].commit.message,
            "AUTHOR" => @old_builds[0].commit.author,
            "SHA" => @old_builds[0].commit.sha,
            "OUTPUT" => @old_builds[0].clean_output
          }
        else
          {}
        end
      env = data.collect { |k, v| %(#{k}=#{v.inspect}) }.join(" ")
      `#{env} sh #{file}`
    end
  end

  # restore current / old build state from disk.
  def restore
    unless @old_builds.length > 0
      clean_builds
      builds = []
      Dir.glob(".git/builds/*") do |file|
        file = File.basename(file)
        builds << file unless (file =~/\./ or file.to_i == 0)
      end
      builds = builds.sort.reverse
      builds.each do |file|
        @old_builds << read_build(file)
      end
    end

    unless @current_build
      @current_build = read_build('current')
    end

    Process.kill(0, @current_build.pid) if @current_build && @current_build.pid
  rescue Errno::ESRCH
    # build pid isn't running anymore. assume previous
    # server died and reset.
    @current_build = nil
  end

  # write build info for build to file.
  def write_build(name, build)
    filename = ".git/builds/#{name}"
    Dir.mkdir '.git/builds' unless File.directory?('.git/builds')
    if build
      build.dump filename
    elsif File.exist?(filename)
      File.unlink filename
    end
  end

  # load build info from file.
  def read_build(name)
    Build.load(".git/builds/#{name}")
  end

  #removes builds older than what is set in the config
  def clean_builds
    numbuilds = Config.cijoe.buildhistory.to_s.to_i
    numbuilds = numbuilds == 0 ? 10 : numbuilds
    builds = []

    #old builds saved with thier name as a timestamp
    Dir.glob(".git/builds/*") do |file|
      file = File.basename(file)
      builds << file unless (file =~/\./ or file.to_i == 0)
    end

    if builds.length > numbuilds
      #sort and reverse, makes the older builds at the end
      builds = builds.sort.reverse
      #remove old builds
      builds[(numbuilds)...(builds.length)].each do |file|
        File.unlink(".git/builds/#{file}") if File.exist? ".git/builds/#{file}"
      end
    end

  end

  def log_for_time(time)
    @old_builds.each do |build|
      return build.output if build.finished_at.to_i.to_s == time.to_s
    end
    "Log not available"
  end

  def failure_for_time(time)
    @old_builds.each do |build|
      return build.faillog if build.finished_at.to_i.to_s == time.to_s and build.faillog.to_s != ""
    end
    "Log not available"
  end
end
