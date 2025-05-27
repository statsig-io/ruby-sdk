module Statsig
  class Memo  

    @global_memo = {}

    def self.for(hash, method, key, disable_evaluation_memoization: false)
      if disable_evaluation_memoization
        return yield
      end

      if key != nil
        method_hash = hash[method]
        unless method_hash
          method_hash = hash[method] = {}
        end

        return method_hash[key] if method_hash.key?(key)
      end

      method_hash[key] = yield
    end
  
    def self.for_global(method, key)
      return self.for(@global_memo, method, key) do
        yield
      end
    end
  end
end