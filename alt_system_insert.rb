
require 'alt_system'

module Kernel
  [:system, :'`'].each { |name|
    remove_method name
    define_method name, &AltSystem.method(name)
  }
end
