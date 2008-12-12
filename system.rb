#
# Copyright (c) 2008 James M. Lawrence
# 
# Permission is hereby granted, free of charge, to any person
# obtaining a copy of this software and associated documentation files
# (the "Software"), to deal in the Software without restriction,
# including without limitation the rights to use, copy, modify, merge,
# publish, distribute, sublicense, and/or sell copies of the Software,
# and to permit persons to whom the Software is furnished to do so,
# subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
# BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
# ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
# CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#

require 'rbconfig'

if Config::CONFIG["host_os"] =~ %r!(msdos|mswin|djgpp|mingw)!
  module SystemRepair
    BINARY_EXTS = %w[com exe]

    BATCHFILE_EXTS = %w[bat] +
      if (t = ENV["COMSPEC"]) and t =~ %r!command\.exe\Z!i
        []
      else
        %w[cmd]
      end

    RUNNABLE_EXTS = BINARY_EXTS + BATCHFILE_EXTS

    RUNNABLE_PATTERN, BINARY_PATTERN, BATCHFILE_PATTERN =
      [RUNNABLE_EXTS, BINARY_EXTS, BATCHFILE_EXTS].map { |exts|
        if exts.size > 1
          %r!\.(#{exts.join('|')})\Z!i
        else
          %r!\.#{exts.first}\Z!i
        end
      }

    class << self
      def define_module_function(name, &block)
        define_method(name, &block)
        module_function(name)
      end
    end

    define_module_function :system_previous, &Kernel.method(:system)
    define_module_function :backticks_previous, &Kernel.method(:'`')

    module_function

    def system(cmd, *args)
      repaired_args = 
        if args.empty?
          [repair_command(cmd)]
        else
          file = cmd.to_s
          if file =~ BATCHFILE_PATTERN
            [join_command(file, *args)]
          else
            if runnable = find_runnable(file)
              [File.expand_path(runnable), *args]
            else
              [join_command(file, *args)]
            end
          end
        end
      if repaired_args.size == 1
        system_previous("call #{repaired_args.first}")
      else
        system_previous(*repaired_args)
      end
    end

    def backticks(cmd)
      backticks_previous(repair_command(cmd))
    end

    def repair_command(cmd)
      if (match = cmd.match(%r!\A\s*\"(.*?)\"!)) or
         (match = cmd.match(%r!\A(\S+)!))
        if runnable = find_runnable(match.captures.first)
          quote(to_backslashes(runnable)) + match.post_match
        else
          cmd
        end
      else
        cmd
      end
    end

    def join_command(*args)
      first =
        if args.first =~ %r!\s!
          quote(args.first)
        else
          args.first
        end
      [to_backslashes(first), *tail(args)].join(" ")
    end

    def to_backslashes(string)
      string.gsub("/", "\\")
    end

    def quote(string)
      %Q!"#{string}"!
    end

    def tail(array)
      array[1..-1]
    end

    def find_runnable(file)
      if file =~ RUNNABLE_PATTERN
        file
      else
        RUNNABLE_EXTS.each { |ext|
          if File.exist?(t = "#{file}.#{ext}")
            return t
          end
        }
        nil
      end
    end
  end

  module Kernel
    remove_method :system
    remove_method :'`'

    define_method :system, &SystemRepair.method(:system)
    define_method :'`', &SystemRepair.method(:backticks)
  end
end
