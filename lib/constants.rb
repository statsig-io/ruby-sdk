require 'set'

module Statsig
  module Const
    EMPTY_STR = ''.freeze

    SUPPORTED_CONDITION_TYPES = Set.new(%i[
                                          public fail_gate pass_gate ip_based ua_based user_field
                                          environment_field current_time user_bucket unit_id
                                        ]).freeze

    SUPPORTED_OPERATORS = Set.new(%i[
                                    gt gte lt lte version_gt version_gte version_lt version_lte
                                    version_eq version_neq any none any_case_sensitive none_case_sensitive
                                    str_starts_with_any str_ends_with_any str_contains_any str_contains_none
                                    str_matches eq neq before after on in_segment_list not_in_segment_list
                                  ]).freeze

    APP_VERSION = 'app_version'.freeze
    APPVERSION = 'appversion'.freeze
    BROWSER_NAME = 'browser_name'.freeze
    BROWSER_VERSION = 'browser_version'.freeze
    BROWSERNAME = 'browsername'.freeze
    BROWSERVERSION = 'browserversion'.freeze
    CML_SHA_256 = 'sha256'.freeze
    CML_USER_ID = 'userID'.freeze
    COUNTRY = 'country'.freeze
    DEFAULT = 'default'.freeze
    DISABLED = 'disabled'.freeze
    DJB2 = 'djb2'.freeze
    EMAIL = 'email'.freeze
    EXPLORE = ':explore'.freeze
    FAILS_TARGETING = 'inlineTargetingRules'.freeze
    FALSE = 'false'.freeze
    IP = 'ip'.freeze
    LAYER = :layer
    LOCALE = 'locale'.freeze
    NONE = 'none'.freeze
    OS_NAME = 'os_name'.freeze
    OS_VERSION = 'os_version'.freeze
    OSNAME = 'osname'.freeze
    OSVERSION = 'osversion'.freeze
    OVERRIDE = 'override'.freeze
    PRESTART = 'prestart'.freeze
    Q_RIGHT_CHEVRON = 'Q>'.freeze
    STABLEID = 'stableid'.freeze
    STATSIG_RUBY_SDK = 'statsig-ruby-sdk'.freeze
    TRUE = 'true'.freeze
    USER_AGENT = 'user_agent'.freeze
    USER_ID = 'user_id'.freeze
    USERAGENT = 'useragent'.freeze
    USERID = 'userid'.freeze
    DICTIONARY = 'dictionary'.freeze
    SEGMENT_PREFIX = 'segment:'.freeze

    DYNAMIC_CONFIG_NAME = 'dynamic_config_name'.freeze
    EXPERIMENT_NAME = 'experiment_name'.freeze
    LAYER_NAME = 'layer_name'.freeze

    # Persisted Evaluations
    GATE_VALUE = 'gate_value'.freeze
    JSON_VALUE = 'json_value'.freeze
    RULE_ID = 'rule_id'.freeze
    SECONDARY_EXPOSURES = 'secondary_exposures'.freeze
    GROUP_NAME = 'group_name'.freeze
    ID_TYPE = 'id_type'.freeze
    TARGET_APP_IDS = 'target_app_ids'.freeze
    CONFIG_SYNC_TIME = 'config_sync_time'.freeze
    INIT_TIME = 'init_time'.freeze

    # Spec Types
    TYPE_FEATURE_GATE = 'feature_gate'.freeze
    TYPE_SEGMENT = 'segment'.freeze
    TYPE_HOLDOUT = 'holdout'.freeze
    TYPE_EXPERIMENT = 'experiment'.freeze
    TYPE_LAYER = 'layer'.freeze
    TYPE_DYNAMIC_CONFIG = 'dynamic_config'.freeze
    TYPE_AUTOTUNE = 'autotune'.freeze

    # API Conditions
    CND_PUBLIC = 'public'.freeze
    CND_IP_BASED = 'ip_based'.freeze
    CND_UA_BASED = 'ua_based'.freeze
    CND_USER_FIELD = 'user_field'.freeze
    CND_PASS_GATE = 'pass_gate'.freeze
    CND_FAIL_GATE = 'fail_gate'.freeze
    CND_MULTI_PASS_GATE = 'multi_pass_gate'.freeze
    CND_MULTI_FAIL_GATE = 'multi_fail_gate'.freeze
    CND_CURRENT_TIME = 'current_time'.freeze
    CND_ENVIRONMENT_FIELD = 'environment_field'.freeze
    CND_USER_BUCKET = 'user_bucket'.freeze
    CND_UNIT_ID = 'unit_id'.freeze

    # API Operators
    OP_GREATER_THAN = 'gt'.freeze
    OP_GREATER_THAN_OR_EQUAL = 'gte'.freeze
    OP_LESS_THAN = 'lt'.freeze
    OP_LESS_THAN_OR_EQUAL = 'lte'.freeze
    OP_ANY = 'any'.freeze
    OP_NONE = 'none'.freeze
    OP_ANY_CASE_SENSITIVE = 'any_case_sensitive'.freeze
    OP_NONE_CASE_SENSITIVE = 'none_case_sensitive'.freeze
    OP_EQUAL = 'eq'.freeze
    OP_NOT_EQUAL = 'neq'.freeze

    # API Operators (Version)
    OP_VERSION_GREATER_THAN = 'version_gt'.freeze
    OP_VERSION_GREATER_THAN_OR_EQUAL = 'version_gte'.freeze
    OP_VERSION_LESS_THAN = 'version_lt'.freeze
    OP_VERSION_LESS_THAN_OR_EQUAL = 'version_lte'.freeze
    OP_VERSION_EQUAL = 'version_eq'.freeze
    OP_VERSION_NOT_EQUAL = 'version_neq'.freeze

    # API Operators (String)
    OP_STR_STARTS_WITH_ANY = 'str_starts_with_any'.freeze
    OP_STR_END_WITH_ANY = 'str_ends_with_any'.freeze
    OP_STR_CONTAINS_ANY = 'str_contains_any'.freeze
    OP_STR_CONTAINS_NONE = 'str_contains_none'.freeze
    OP_STR_MATCHES = 'str_matches'.freeze

    # API Operators (Time)
    OP_BEFORE = 'before'.freeze
    OP_AFTER = 'after'.freeze
    OP_ON = 'on'.freeze

    # API Operators (Segments)
    OP_IN_SEGMENT_LIST = 'in_segment_list'.freeze
    OP_NOT_IN_SEGMENT_LIST = 'not_in_segment_list'.freeze

    # API Operators (Array)
    OP_ARRAY_CONTAINS_ANY = 'array_contains_any'.freeze
    OP_ARRAY_CONTAINS_NONE = 'array_contains_none'.freeze
    OP_ARRAY_CONTAINS_ALL = 'array_contains_all'.freeze
    OP_NOT_ARRAY_CONTAINS_ALL = 'not_array_contains_all'.freeze
  end
end
