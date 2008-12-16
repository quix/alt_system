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

#
# Specification of system() and backticks `` for Windows.
#

require 'rbconfig'

unless Config::CONFIG["host_os"] =~ %r!(msdos|mswin|djgpp|mingw)!
  raise "This specification is for Windows only."
end

begin
  require 'spec'
rescue LoadError
  require 'rubygems'
  require 'spec'
end

require 'base64'
require 'fileutils'
include FileUtils

OLD_SYSTEM = ARGV.include?("--old")

unless OLD_SYSTEM
  require 'alt_system_insert'
end

RUBY_COMMAND_STRING = %{
  File.join(Config::CONFIG["bindir"], Config::CONFIG["ruby_install_name"])
}.strip

RUBY_COMMAND = eval RUBY_COMMAND_STRING 

DATA_DIR = "test_data"
EXPANSION_TEST = "expansion.rb"
RESULT_DATA = "result.txt"
DUMMY_EXE = "dummy.exe"

STEMS = [
  "a",
  "b c",
  "d/e",
  "f/g h",
  "i j/k",
  "l m/n o",
  "p/q/r",
  "s t/u v/w x/y z",
]

############################################################
# util
############################################################

#
# ***NOTE*** cut & paste from system.rb.
# These constants do not exist for --old option.
#
BINARY_EXTS = %w[com exe]
BATCHFILE_EXTS = %w[bat] +
  if (t = ENV["COMSPEC"]) and t =~ %r!command\.exe\Z!i
    []
  else
    %w[cmd]
  end
RUNNABLE_EXTS = BINARY_EXTS + BATCHFILE_EXTS

def quote(string)
  %Q!"#{string}"!
end

def append_ext(file, ext)
  if ext.empty?
    file
  else
    "#{file}.#{ext}"
  end
end

def check_backticks_success
  $?.should_not == nil and $?.exitstatus.should == 0
end

def with_env_var(name, value)
  previous = ENV[name]
  ENV[name] = value
  begin
    yield
  ensure
    if previous
      ENV[name] = previous
    else
      ENV.delete(name)
    end
  end
end

############################################################
# create test data
############################################################

def create_batchfile(file)
  mkdir_p File.dirname(file)
  File.open(file, "w") { |out|
    out.puts %Q{
      @echo off
      echo #{file}
      echo #{file} > #{RESULT_DATA}
    }
  }
end

def create_binary(file)
  mkdir_p File.dirname(file)
  cp(DUMMY_EXE, file)
end

def create_first_dummy_exe
  c_file = "noop.c"
  File.open(c_file, "w") { |out|
    out.puts %q{
      int main() { return 0 ; }
    }
  }
  system(*%W[gcc #{c_file} -o #{DUMMY_EXE} -mno-cygwin -Os -s]) or raise
  File.open("dumped", "w") { |out|
    out.print Base64.encode64(File.read(DUMMY_EXE))
  }
end

def create_dummy_exe
  File.open(File.join(DATA_DIR, DUMMY_EXE), "wb") { |out|
    out.print(DUMMY_EXE_CONTENTS)
  }
end

############################################################
# create examples
############################################################

def command_desc(*args)
  args.join(", ")
end

def create_batchfile_example(cmd, file, args = [])
  before do
    unless File.exist? file
      create_batchfile(file)
    end
  end
  desc = command_desc(cmd, *args)
  it "#{desc} should succeed" do
    system(cmd, *args).should == true
  end
  it "#{desc} should run the correct file" do
    File.read(RESULT_DATA).strip.should == file
  end
  if args.empty?
    it "`#{desc}` should succeed and obtain correct data (backticks)" do
      `#{cmd}`.strip.should == file
    end
    it "`#{desc}` should exit cleanly (backticks)" do
      check_backticks_success
    end
  end
end

def create_binary_example(cmd, file, args = [])
  before do
    unless File.exist? file
      create_binary(file)
    end
  end
  it command_desc(cmd, *args) do
    system(cmd, *args).should == true
  end
end

def create_example(spec)
  absolute_path = File.expand_path(File.join(DATA_DIR, spec[:stem]))
  stem = 
    if spec[:path_type] == :absolute
      absolute_path
    else
      spec[:stem]
    end
  cmd = append_ext(stem, spec[:cmd_ext])
  file = append_ext(absolute_path, spec[:file_ext])
  has_space = (cmd =~ %r!\s!)
  creator = method(
    if BATCHFILE_EXTS.include? spec[:file_ext]
      :create_batchfile_example
    else
      :create_binary_example
    end)

  if spec[:args].empty?
    unless has_space
      describe "unquoted" do
        creator.call(cmd, file)
      end
    end
    
    describe "quoted" do
      creator.call(quote(cmd), file)
    end
  else
    case spec[:pass_args]
    when :string
      concat = lambda { |t|
        t + " " + spec[:args].join(" ")
      }
      
      unless has_space
        describe "unquoted" do
          creator.call(concat.call(cmd), file)
        end
      end
      
      describe "quoted" do
        creator.call(concat.call(quote(cmd)), file)
      end
    when :ruby
      creator.call(cmd, file, spec[:args])
    else
      raise
    end
  end
end

def create_examples(spec)
  STEMS.each { |stem|
    create_example(spec.merge(:stem => stem))
  }
end

def create_example_group(spec)
  describe "with relative path" do
    create_examples(spec.merge(:path_type => :relative))
  end
  
  describe "with absolute path" do
    create_examples(spec.merge(:path_type => :absolute))
  end
end

def create_example_set(cmd_ext, file_ext)
  spec = {
    :cmd_ext => cmd_ext,
    :file_ext => file_ext,
  }

  describe "with no arguments" do
    create_example_group(spec.merge(:args => []))
  end
  
  describe "with arguments" do
    arg_spec = spec.merge(:args => ["1", "2"])
    
    describe "passed via ruby" do
      create_example_group(arg_spec.merge(:pass_args => :ruby))
    end
    
    describe "passed via command string" do
      create_example_group(arg_spec.merge(:pass_args => :string))
    end
  end

  #
  # It is not possible for batchfiles to take arguments with whitespace.
  # http://www.cygwin.com/ml/cygwin/2004-09/msg00277.html
  #
  #describe "with whitespace-containing arguments" do
  #end
  #
end

def create_example_sets(ext)
  describe "should run .#{ext} files" do
    create_example_set(ext, ext)
  end

  describe "should find .#{ext} files with no-extension invocation" do
    create_example_set("", ext)
  end
end

def create_basic_examples
  before :all do
    @pwd = Dir.pwd
    rm_rf(DATA_DIR)
    mkdir(DATA_DIR)
    create_dummy_exe
  end
    
  after :all do
    rm_r(DATA_DIR)
  end
    
  before :each do
    Dir.chdir(DATA_DIR)
  end
    
  after :each do
    Dir.chdir(@pwd)
  end
    
  RUNNABLE_EXTS.sort.each { |ext|
    create_example_sets(ext)
  }
end

def create_builtin_examples
  describe "with built-in commands such as echo" do
    it "should succeed with no arguments" do
      system("echo").should == true
    end
    it "should succeed with arguments passed via command string" do
      system("echo 1 2").should == true
    end
    it "should fail with arguments passed via ruby" do
      system("echo", "1", "2").should == false
    end
    it "should succeed and obtain correct data with backticks" do
      `echo 1 2`.strip.should == "1 2"
    end
    it "should exit cleanly with backticks" do
      check_backticks_success
    end
  end
end

def create_ruby_command_examples
  describe "with joined config parameters #{RUBY_COMMAND_STRING}" do
    it "should succeed with arguments passed via command string" do
      system(%{#{RUBY_COMMAND} -e "x = 1"}).should == true
    end
    it "should succeed with arguments passed via ruby" do
      system(RUBY_COMMAND, "-e", "x = 1").should == true
    end
  end
end

def create_variable_expansion_examples
  name, value = ["TEST_VAR", "--some-value--"]
  name_deref = "%#{name}%"
  cmd_array = [RUBY_COMMAND, EXPANSION_TEST, name_deref]
  cmd_string = cmd_array.join(" ")
  result = lambda { File.read(RESULT_DATA).strip }

  describe "variable expansion" do
    before do
      unless File.exist? EXPANSION_TEST
        File.open(EXPANSION_TEST, "w") { |expansion_test|
          expansion_test.puts %{
            File.open("#{RESULT_DATA}", "w") { |result_data|
              result_data.puts(ARGV.first)
            }
            puts(ARGV.first)
          }
        }
      end
    end

    it "should expand arguments passed via command string" do
      with_env_var(name, value) {
        system(cmd_string).should == true
        result.call.should == value
      }
    end
    it "should expand arguments passed via command string (backticks)" do
      with_env_var(name, value) {
        `#{cmd_string}`.strip.should == value
        check_backticks_success
      }
    end
    it "should not expand arguments passed via ruby" do
      with_env_var(name, value) {
        system(*cmd_array).should == true
        result.call.should == name_deref
      }
    end
  end
end

#
# Cannot raise Errno::ENOENT for nonexisting files because 'call' is
# necessary.
#

def create_empty_examples
  describe "with empty argument(s)" do
    it "should fail with one empty argument" do
      system("").should == false
    end
    #it "should raise Errno::ENOENT with one empty argument (backticks)" do
    #  lambda { `` }.should raise_error(Errno::ENOENT)
    #end
    it "should fail with multiple empty arguments passed via ruby" do
      system("", "").should == false
    end
  end
end

def create_nonexistent_examples
  {
    "with nonexistent batch file" => ".bat",
    "with nonexistent command" => "",
  }.each_pair { |desc, ext|
    describe desc do
      cmd = rand.to_s + ext
      raise if File.exist?(cmd)
  
      it "should fail with no arguments" do
        system(cmd).should == false
      end
      #it "should raise Errno::ENOENT with no arguments (backticks)" do
      #  lambda { `#{cmd}` }.should raise_error(Errno::ENOENT)
      #end
      it "should fail with multiple arguments passed via command string" do
        system("#{cmd} 1 2").should == false
      end
      #it "should raise Errno::ENOENT with multiple arguments " +
      #  "passed via command string (backticks)" do
      #  lambda { `#{cmd} 1 2` }.should raise_error(Errno::ENOENT)
      #end
      it "should fail with multiple arguments passed via ruby" do
        system(cmd, "1", "2").should == false
      end
    end
  }
end

############################################################
# top-level specification
############################################################

describe((OLD_SYSTEM ? "(OLD)" : "(NEW)") + " system()") do
  create_basic_examples
  create_builtin_examples
  create_ruby_command_examples
  create_variable_expansion_examples
  create_empty_examples
  create_nonexistent_examples
end

############################################################
# data
############################################################

DUMMY_EXE_CONTENTS = Base64.decode64 '
TVqQAAMAAAAEAAAA//8AALgAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAgAAAAA4fug4AtAnNIbgBTM0hVGhpcyBwcm9ncmFt
IGNhbm5vdCBiZSBydW4gaW4gRE9TIG1vZGUuDQ0KJAAAAAAAAABQRQAATAEE
AG5/FkkAAAAAAAAAAOAADwMLAQI4AAYAAAAEAAAAAgAAgBIAAAAQAAAAIAAA
AABAAAAQAAAAAgAABAAAAAEAAAAEAAAAAAAAAABQAAAABAAASaQAAAMAAAAA
ACAAABAAAAAAEAAAEAAAAAAAABAAAAAAAAAAAAAAAABAAACwAQAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAC50ZXh0AAAAMAUAAAAQAAAABgAAAAQAAAAAAAAA
AAAAAAAAACAAUGAuZGF0YQAAAAwAAAAAIAAAAAIAAAAKAAAAAAAAAAAAAAAA
AABAADDALmJzcwAAAABIAAAAADAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgABA
wC5pZGF0YQAAsAEAAABAAAAAAgAAAAwAAAAAAAAAAAAAAAAAAEAAMMAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
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
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAQEAAAAAAAAAAAAAAjEEAAIBAAABwQAAAAAAAAAAAAACg
QQAAsEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAALxAAADMQAAA3EAAAOpA
AAD8QAAABkEAAA5BAAAYQQAAJEEAAC5BAAAAAAAAAAAAADhBAABGQQAAAAAA
AAAAAAC8QAAAzEAAANxAAADqQAAA/EAAAAZBAAAOQQAAGEEAACRBAAAuQQAA
AAAAAAAAAAA4QQAARkEAAAAAAAAnAF9fZ2V0bWFpbmFyZ3MAPABfX3BfX2Vu
dmlyb24AAD4AX19wX19mbW9kZQAAUABfX3NldF9hcHBfdHlwZQAAeQBfY2V4
aXQAAOkAX2lvYgAAXgFfb25leGl0AIQBX3NldG1vZGUAABwCYXRleGl0AACQ
AnNpZ25hbAAAnABFeGl0UHJvY2VzcwDjAlNldFVuaGFuZGxlZEV4Y2VwdGlv
bkZpbHRlcgAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAA
QAAAbXN2Y3J0LmRsbAAAFEAAABRAAABLRVJORUwzMi5kbGwAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
'
