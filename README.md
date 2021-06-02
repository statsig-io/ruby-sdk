# Statsig Ruby SDK

```ruby
require 'statsig'

Statsig.initialize('<secret>')

user = StatsigUser.new
user.user_id = '12345'
user.email = 'tore@statsig.com'

if Statsig.check_gate(user, 'my_feature_gate')
  # show your feature
end
```
