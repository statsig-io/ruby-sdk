# typed: true
module Statsig
  class IDList
    attr_accessor :name
    attr_accessor :size
    attr_accessor :creation_time
    attr_accessor :url
    attr_accessor :file_id
    attr_accessor :ids

    def initialize(json, ids = Set.new)
      @name = json['name'] || ''
      @size = json['size'] || 0
      @creation_time = json['creationTime'] || 0
      @url = json['url']
      @file_id = json['fileID']

      @ids = ids
    end

    def self.new_empty(json)
      new(json)
      @size = 0
    end

    def ==(other)
      return false if other.nil?

      self.name == other.name &&
        self.size == other.size &&
        self.creation_time == other.creation_time &&
        self.url == other.url &&
        self.file_id == other.file_id &&
        self.ids == other.ids
    end
  end
end