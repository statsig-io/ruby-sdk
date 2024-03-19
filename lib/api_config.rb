require 'constants'

class UnsupportedConfigException < StandardError
end

module Statsig
  class APIConfig
    attr_accessor :name, :type, :is_active, :salt, :default_value, :enabled,
                  :rules, :id_type, :entity, :explicit_parameters, :has_shared_params, :target_app_ids

    def self.from_json(json)
      new(
        name: json[:name],
        type: json[:type],
        is_active: json[:isActive],
        salt: json[:salt],
        default_value: json[:defaultValue] || {},
        enabled: json[:enabled],
        rules: json[:rules]&.map do |rule|
          APIRule.from_json(rule)
        end,
        id_type: json[:idType],
        entity: json[:entity],
        explicit_parameters: json[:explicitParameters],
        has_shared_params: json[:hasSharedParams],
        target_app_ids: json[:targetAppIDs]
      )
    end

    private

    def initialize(name:, type:, is_active:, salt:, default_value:, enabled:, rules:, id_type:, entity:,
                   explicit_parameters: nil, has_shared_params: nil, target_app_ids: nil)
      @name = name
      @type = type.to_sym unless type.nil?
      @is_active = is_active
      @salt = salt
      @default_value = JSON.parse(JSON.generate(default_value))
      @enabled = enabled
      @rules = rules
      @id_type = id_type
      @entity = entity.to_sym unless entity.nil?
      @explicit_parameters = explicit_parameters
      @has_shared_params = has_shared_params
      @target_app_ids = target_app_ids
    end
  end

  class APIRule

    attr_accessor :name, :pass_percentage, :return_value, :id, :salt,
                  :conditions, :id_type, :group_name, :config_delegate, :is_experiment_group

    def self.from_json(json)
      new(
        name: json[:name],
        pass_percentage: json[:passPercentage],
        return_value: json[:returnValue] || {},
        id: json[:id],
        salt: json[:salt],
        conditions: json[:conditions]&.map do |condition|
          APICondition.from_json(condition)
        end,
        id_type: json[:idType],
        group_name: json[:groupName],
        config_delegate: json[:configDelegate],
        is_experiment_group: json[:isExperimentGroup]
      )
    end

    private

    def initialize(name:, pass_percentage:, return_value:, id:, salt:, conditions:, id_type:,
                   group_name: nil, config_delegate: nil, is_experiment_group: nil)
      @name = name
      @pass_percentage = pass_percentage.to_f
      @return_value = JSON.parse(JSON.generate(return_value))
      @id = id
      @salt = salt
      @conditions = conditions
      @id_type = id_type
      @group_name = group_name
      @config_delegate = config_delegate
      @is_experiment_group = is_experiment_group
    end
  end

  class APICondition

    attr_accessor :type, :target_value, :operator, :field, :additional_values, :id_type, :hash

    def self.from_json(json)
      operator = json[:operator]
      unless operator.nil?
        operator = operator&.downcase&.to_sym
        unless Const::SUPPORTED_OPERATORS.include?(operator)
          raise UnsupportedConfigException
        end
      end

      type = json[:type]
      unless type.nil?
        type = type&.downcase&.to_sym
        unless Const::SUPPORTED_CONDITION_TYPES.include?(type)
          raise UnsupportedConfigException
        end
      end

      new(
        type: json[:type],
        target_value: json[:targetValue],
        operator: json[:operator],
        field: json[:field],
        additional_values: json[:additionalValues],
        id_type: json[:idType],
        hash: Statsig::HashUtils.md5(json.to_s)
      )
    end

    private

    def initialize(type:, target_value:, operator:, field:, additional_values:, id_type:, hash:)
      @hash = hash
      
      @type = type.to_sym unless type.nil?
      if operator == "any_case_sensitive" || operator == "none_case_sensitive"
        if target_value.is_a?(Array)
            target_value = target_value.map { |item| [item.to_s, true] }.to_h
        end
      end
      if operator == "any" || operator == "none"
        if target_value.is_a?(Array)
            target_value = target_value.map { |item| [item.to_s.downcase, true] }.to_h
        end
      end
      @target_value = target_value
      @operator = operator.to_sym unless operator.nil?
      @field = field
      @additional_values = additional_values || {}
      @id_type = id_type
    end
  end
end
