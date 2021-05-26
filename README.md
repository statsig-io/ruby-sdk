# Statsig Ruby SDK

```
gem build && gem install ./statsig-0.0.0.gem && irb

require 'statsig'

s = Statsig.new('<secret>')

s.check_gate('always_on_gate')
```
