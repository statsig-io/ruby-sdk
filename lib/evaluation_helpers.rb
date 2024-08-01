require 'time'

module EvaluationHelpers
  def self.compare_numbers(a, b, func)
    return false unless is_numeric(a) && is_numeric(b)
    func.call(a.to_f, b.to_f) rescue false
  end

  # returns true if array has any element that evaluates to true with value using func lambda, ignoring case
  def self.match_string_in_array(array, value, ignore_case, func)
    str_value = value.to_s
    str_value_downcased = nil
    return false if array.nil?

    return array.any? do |item|
      next false if item.nil?
      item_str = item.to_s

      return true if func.call(str_value, item_str)
      next false unless ignore_case

      str_value_downcased ||= str_value.downcase
      func.call(str_value_downcased, item_str.downcase)
    end
  end

  def self.equal_string_in_array(array, value, ignore_case)
    if array.is_a?(Hash)
      return array.has_key?(value.to_sym)
    end

    str_value = value.to_s
    str_value_downcased = nil

    return false if array.nil?

    return array.any? do |item|
      next false if item.nil?
      item_str = item.to_s

      next false unless item_str.length == str_value.length

      return true if item_str == str_value
      next false unless ignore_case

      str_value_downcased ||= str_value.downcase
      item_str.downcase == str_value_downcased
    end
  end

  def self.compare_times(a, b, func)
    begin
      time_1 = get_epoch_time(a)
      time_2 = get_epoch_time(b)
      func.call(time_1, time_2)
    rescue
      false
    end
  end

  private

  def self.is_numeric(v)
    return true if v.is_a?(Numeric)
    !(v.to_s =~ /\A[-+]?\d*\.?\d+\z/).nil?
  end

  def self.get_epoch_time(v)
    time = is_numeric(v) ? Time.at(v.to_f) : Time.parse(v)
    if time.year > Time.now.year + 100
      # divide by 1000 when the epoch time is in milliseconds instead of seconds
      return time.to_i / 1000
    end
    return time.to_i
  end
end