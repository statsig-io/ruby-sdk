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
    Q_RIGHT_CHEVRON = 'Q>'.freeze
    STABLEID = 'stableid'.freeze
    STATSIG_RUBY_SDK = 'statsig-ruby-sdk'.freeze
    TRUE = 'true'.freeze
    USER_AGENT = 'user_agent'.freeze
    USER_ID = 'user_id'.freeze
    USERAGENT = 'useragent'.freeze
    USERID = 'userid'.freeze

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
  end
end
