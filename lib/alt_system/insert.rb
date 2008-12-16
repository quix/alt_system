
require 'alt_system'

if defined? AltSystem
  module Kernel
    [:system, :'`'].each { |name|
      remove_method name
      define_method name, &AltSystem.method(name)
    }
  end
end
