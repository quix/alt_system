
require 'alt_system/alt_system'

if AltSystem::WINDOWS
  module Kernel
    [:system, :'`'].each { |name|
      remove_method name
      define_method name, &AltSystem.method(name)
    }
  end
end
