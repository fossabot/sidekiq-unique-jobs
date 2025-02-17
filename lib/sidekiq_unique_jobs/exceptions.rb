# frozen_string_literal: true

module SidekiqUniqueJobs
  #
  # Base class for all exceptions raised from the gem
  #
  # @author Mikael Henriksson <mikael@zoolutions.se>
  #
  class UniqueJobsError < ::RuntimeError
  end

  # Error raised when a Lua script fails to execute
  #
  # @author Mikael Henriksson <mikael@zoolutions.se>
  class Conflict < UniqueJobsError
    def initialize(item)
      super("Item with the key: #{item[UNIQUE_DIGEST]} is already scheduled or processing")
    end
  end

  #
  # Error raised when trying to add a duplicate lock
  #
  # @author Mikael Henriksson <mikael@zoolutions.se>
  #
  class DuplicateLock < UniqueJobsError
  end

  #
  # Error raised when trying to add a duplicate stragegy
  #
  # @author Mikael Henriksson <mikael@zoolutions.se>
  #
  class DuplicateStrategy < UniqueJobsError
  end

  #
  # Error raised when an invalid argument is given
  #
  # @author Mikael Henriksson <mikael@zoolutions.se>
  #
  class InvalidArgument < UniqueJobsError
  end

  #
  # Raised when a workers configuration is invalid
  #
  # @author Mikael Henriksson <mikael@zoolutions.se>
  #
  class InvalidWorker < UniqueJobsError
    def initialize(lock_config)
      super(<<~FAILURE_MESSAGE)
        Expected #{lock_config.worker} to have valid sidekiq options but found the following problems:
        #{lock_config.errors_as_string}
      FAILURE_MESSAGE
    end
  end

  # Error raised when a Lua script fails to execute
  #
  # @author Mikael Henriksson <mikael@zoolutions.se>
  class InvalidUniqueArguments < UniqueJobsError
    def initialize(given:, worker_class:, unique_args_method:)
      uniq_args_meth  = worker_class.method(unique_args_method)
      num_args        = uniq_args_meth.arity
      # source_location = uniq_args_meth.source_location

      super(
        "#{worker_class}#unique_args takes #{num_args} arguments, received #{given.inspect}"
      )
    end
  end

  #
  # Raised when a workers configuration is invalid
  #
  # @author Mikael Henriksson <mikael@zoolutions.se>
  #
  class NotUniqueWorker < UniqueJobsError
    def initialize(options: {})
      super("#{options[:class]} is not configured for uniqueness. Missing the key `:lock` in #{options.inspect}")
    end
  end

  # Error raised from {OnConflict::Raise}
  #
  # @author Mikael Henriksson <mikael@zoolutions.se>
  class ScriptError < UniqueJobsError
    # Reformats errors raised by redis representing failures while executing
    # a lua script. The default errors have confusing messages and backtraces,
    # and a type of +RuntimeError+. This class improves the message and
    # modifies the backtrace to include the lua script itself in a reasonable
    # way.

    PATTERN  = /ERR Error (compiling|running) script \(.*?\): .*?:(\d+): (.*)/.freeze
    LIB_PATH = File.expand_path("..", __dir__)
    CONTEXT_LINE_NUMBER = 3

    attr_reader :error, :file, :content

    # Is this error one that should be reformatted?
    #
    # @param error [StandardError] the original error raised by redis
    # @return [Boolean] is this an error that should be reformatted?
    def self.intercepts?(error)
      error.message =~ PATTERN
    end

    # Initialize a new {ScriptError} from an existing redis error, adjusting
    # the message and backtrace in the process.
    #
    # @param error [StandardError] the original error raised by redis
    # @param file [Pathname] full path to the lua file the error ocurred in
    # @param content [String] lua file content the error ocurred in
    # :nocov:
    def initialize(error, file, content)
      @error        = error
      @file         = file
      @content      = content
      @backtrace    = @error.backtrace

      @error.message.match(PATTERN) do |regexp_match|
        line_number   = regexp_match[2].to_i
        message       = regexp_match[3]
        error_context = generate_error_context(content, line_number)

        super("#{message}\n\n#{error_context}\n\n")
        set_backtrace(generate_backtrace(file, line_number))
      end
    end

    private

    # :nocov:
    def generate_error_context(content, line_number)
      lines                 = content.lines.to_a
      beginning_line_number = [1, line_number - CONTEXT_LINE_NUMBER].max
      ending_line_number    = [lines.count, line_number + CONTEXT_LINE_NUMBER].min
      line_number_width     = ending_line_number.to_s.length

      (beginning_line_number..ending_line_number).map do |number|
        indicator = (number == line_number) ? "=>" : "  "
        formatted_number = format("%#{line_number_width}d", number)
        " #{indicator} #{formatted_number}: #{lines[number - 1]}"
      end.join.chomp
    end

    # :nocov:
    def generate_backtrace(file, line_number)
      pre_gem                         = backtrace_before_entering_gem(@backtrace)
      index_of_first_unique_jobs_line = (@backtrace.size - pre_gem.size - 1)
      pre_gem.unshift(@backtrace[index_of_first_unique_jobs_line])
      pre_gem.unshift("#{file}:#{line_number}")
      pre_gem
    end

    # :nocov:
    def backtrace_before_entering_gem(backtrace)
      backtrace.reverse.take_while { |line| !line_from_gem(line) }.reverse
    end

    # :nocov:
    def line_from_gem(line)
      line.split(":").first.include?(LIB_PATH)
    end
  end

  # Error raised from {OptionsWithFallback#lock_class}
  #
  # @author Mikael Henriksson <mikael@zoolutions.se>
  class UnknownLock < UniqueJobsError
  end
end
