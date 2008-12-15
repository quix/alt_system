
require 'rake'
require 'spec/rake/spectask'

SPEC = "system_spec.rb"

ENGINE = 
  if defined? RUBY_ENGINE
    RUBY_ENGINE
  else
    "ruby"
  end

@raw_output = nil
@rcov = nil

def run_spec(which)
  tag = ENGINE == "ruby" ? "" : "_" + ENGINE
  stem = SPEC.sub(%r!\.rb\Z!, "") + "#{tag}_#{which}"

  if @raw_output
    # text format and redirect to record hard errors
    system("spec -fs #{SPEC} -- --#{which} > #{stem}.txt 2>&1")
  else
    Spec::Rake::SpecTask.new(which.to_s) do |t|
      t.spec_files = FileList[SPEC]
      t.spec_opts = ["--format", "html:#{stem}.html", "--", "--#{which}"]
      if @rcov
        t.rcov = true
      end
    end
  end
end

task :raw_output do
  @raw_output = true
end

task :rcov do
  @rcov = true
end

task :engine do
  puts ENGINE
end

[:new, :old].each { |which|
  task which do
    run_spec(which)
  end
  task :default => which
}
