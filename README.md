[![Build Status](https://travis-ci.org/Originate/end_state.svg?branch=master)](https://travis-ci.org/Originate/end_state)
[![Code Climate](https://codeclimate.com/github/Originate/end_state/badges/gpa.svg)](https://codeclimate.com/github/Originate/end_state)
[![Coverage Status](https://coveralls.io/repos/Originate/end_state/badge.png)](https://coveralls.io/r/Originate/end_state)

# EndState

EndState is an unobtrusive way to add state machines to your application.

An `EndState::StateMachine` acts as a decorator of sorts for your stateful object.
Your stateful object does not need to know it is being used in a state machine and
only needs to respond to `state` and `state=`. (This is customizable)

The control flow for guarding against transitions and performing post-transition
operations is handled by classes you create allowing maximum separation of responsibilities.

## Installation

Add this line to your application's Gemfile:

    gem 'end_state'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install end_state

## StateMachine

Create a state machine by subclassing `EndState::StateMachine`.
Transitions can be named by adding an `:as` option.

```ruby
class Machine < EndState::StateMachine
  transition parked: :idling, as: :start
  transition idling: :first_gear, first_gear: :second_gear, second_gear: :third_gear, as: :shift_up
  transition third_gear: :second_gear, second_gear: :first_gear, as: :shift_down
  transition first_gear: :idling, as: :idle
  transition [:idling, :first_gear] => :parked, as: :park
end
```

Use it by wrapping a stateful object.

```ruby
class StatefulObject
  attr_accessor :state

  def initialize(state)
    @state = state
  end
end

machine = Machine.new(StatefulObject.new(:parked))

machine.transition :idling            # => true
machine.state                         # => :idling
machine.idling?                       # => true
machine.transition :first_gear        # => true
machine.transition :second_gear       # => true
machine.transition :third_gear        # => true
machine.state                         # => :third_gear
machine.can_transition? :first_gear   # => false
machine.can_transition? :second_gear  # => true
machine.transition :first_gear        # => false
machine.transition! :first_gear       # => raises InvalidTransition
machine.shift_down                    # => true
machine.shift_up                      # => true
machine.state                         # => :third_gear
machine.park                          # => false
machine.park!                         # => raises InvalidTransition
```

## Initial State

If you wrap an object that currently has `nil` as the state, the state will be set to `:__nil__`.
You can change this using the `set_initial_state` method.

```ruby
class Machine < EndState::StateMachine
  set_initial_state :first
end
```

## Special State - :any_state

You can specify the special state `:any_state` as the beginning of a transition. This will allow
the machine to transition to the new state specified from any actual state.

```ruby
class Machine < EndState::StateMachine
  transition parked: :idling
  transition idling: :first_gear
  transition any_state: :crashed
end

machine = Machine.new(StatefulObject.new(:parked))
machine.transition :crashed  # true
machine.state                # :crashed

machine = Machine.new(StatefulObject.new(:parked))
machine.transition :idling   # true
machine.transition :crashed  # true
machine.state                # :crashed
```

## Guards

Guards can be created by subclassing `EndState::Guard`. Your class will be provided access to:

* `object` - The wrapped object.
* `state` - The desired state.
* `params` - A hash of params passed when calling transition on the machine.

Your class should implement the `will_allow?` method which must return true or false.

Optionally you can implement the `passed` and/or `failed` methods which will be called after the guard passes or fails.
These will only be called during the check performed during the transition and will not be fired when asking `can_transition?`.
These hooks can be useful for things like logging.

The wrapped object has an array `failure_messages` available for tracking reasons for invalid transitions. You may shovel
a reason (string) into this if you want to provide information on why your guard failed. You can also use the helper method in
the `Guard` class called `add_error` which takes a string.

The wrapped object has an array `success_messages` available for tracking reasons for valid transitions. You may shovel
a reason (string) into this if you want to provide information on why your guard passed. You can also use the helper method in
the `Guard` class called `add_success` which takes a string.

```ruby
class EasyGuard < EndState::Guard
  def will_allow?
    true
  end

  def failed
    Rails.logger.error "Failed to transition to state #{state} from #{object.state}."
  end
end
```

A guard can be added to the transition definition:

```ruby
class Machine < EndState::StateMachine
  transition a: :b do |t|
    t.guard EasyGuard
    t.guard SomeOtherGuard
  end
end
```

## Concluders

Concluders can be created by subclassing `EndState::Concluder`. Your class will be provided access to:

* `object` - The wrapped object that has been transitioned.
* `state` - The previous state.
* `params` - A hash of params passed when calling transition on the machine.

Your class should implement the `call` method which should return true or false as to whether it was successful or not.

If your concluder returns false, the transition will be "rolled back" and the failing transition, as well as all previous transitions
will be rolled back. The roll back is performed by calling `rollback` on the concluder. During the roll back the concluder will be
set up a little differently and you have access to:

* `object` - The wrapped object that has been rolled back.
* `state` - The attempted desired state.
* `params` - A hash of params passed when calling transition on the machine.

The wrapped object has an array `failure_messages` available for tracking reasons for invalid transitions. You may shovel
a reason (string) into this if you want to provide information on why your concluder failed. You can also use the helper method in
the `Concluder` class called `add_error` which takes a string.

The wrapped object has an array `success_messages` available for tracking reasons for valid transitions. You may shovel
a reason (string) into this if you want to provide information on why your concluder succeeded. You can also use the helper method in
the `Concluder` class called `add_success` which takes a string.

```ruby
class WrapUp < EndState::Concluder
  def call
    # Some important processing
    true
  end

  def rollback
    # Undo stuff that shouldn't have been done.
  end
end
```

A concluder can be added to the transition definition:

```ruby
class Machine < EndState::StateMachine
  transition a: :b do |t|
    t.concluder WrapUp
  end
end
```

Since it is a common use case, a concluder is included which will call `save` on the wrapped object if it responds to `save`.
You can use this with a convience method in your transition definition:

```ruby
class Machine < EndState::StateMachine
  transition a: :b do |t|
    t.persistence_on
  end
end
```

## Action

By default, a transition from one state to another is handled by `EndState` and only changes the state to the new state.
This is the recommended default and you should have a good reason to do something more or different.
If you really want to do something different though you can create a class that subclasses `EndState::Action` and implement
the `call` method.

You will have access to:

* `object` - The wrapped object.
* `state` - The desired state.

```ruby
class MyCustomAction < EndState::Action
  def call
    # Do something special
    super
  end
end
```

```ruby
class Machine < EndState::StateMachine
  transition a: :b do |t|
    t.custom_action MyCustomAction
  end
end
```

## Events

By using the `as` option in a transition definition you are creating an event representing that transition.
This can allow you to exercise the machine in a more natural "verb" style interaction. Events, like `transition`
have both a standard and a bang (`!`) style. The bang style will raise an exception if there is a problem.

```ruby
class Machine < EndState::StateMachine
  transition a: :b, as: :go
end

machine = Machine.new(StatefulObject.new(:a))

machine.go                  # => true
machine.state               # => :b
machine.go                  # => false
machine.go!                 # => raises InvalidTransition
```

## Parameters

When calling a transition, you can optionally provide a hash of parameters which will be available to the guards
and concluders you include in the transition definition.

When defining a transition you can indicate what parameters you are expecting with `allow_params` and `require_params`.
If you require any params then attempting to transition without them provided will raise an error. Specifying allowed
params is purely for documentation purposes.

```ruby
class Machine < EndState::StateMachine
  transition a: :b, as: :go do |t|
    t.allow_params :foo, :bar
  end
end
```

```ruby
class Machine < EndState::StateMachine
  transition a: :b, as: :go do |t|
    t.require_params :foo, :bar
  end
end

machine = Machine.new(StatefulObject.new(:a))
machine.transition :b                         # => error raised: 'Missing params: foo, bar'
machine.transition :b, foo: 1, bar: 'value'   # => true

machine = Machine.new(StatefulObject.new(:a))
machine.go                        # => error raised: 'Missing params: foo, bar'
machine.go foo: 1, bar: 'value'   # => true
```

## State storage

You may want to use an attribute other than `state` to track the state of the machine.

```ruby
class Machine < EndState::StateMachine
  state_attribute :status
end
```

Depending on how you persist the `state` (if at all) you may want what is stored in `state` to be a string instead
of a symbol. You can tell the machine this preference.

```ruby
class Machine < EndState::StateMachine
  store_states_as_strings!
end
```

## Exceptions for failing Transitions

By default `transition` will only raise an error, `EndState::UnknownState`, if called with a state that doesn't exist.
All other failures, such as missing transition, guard failure, or concluder failure will silently just return `false` and not
transition to the new state.

You also have the option to use `transition!` which will instead raise an error for failures. If your guards and/or concluders
add to the `failure_messages` array then they will be included in the error message.

Additionally, if you would like to treat all transitions as hard and raise an error you can set that in the machine definition.

```ruby
class Machine < EndState::StateMachine
  treat_all_transitions_as_hard!
end
```

## Graphing

If you install `GraphViz` and the gem `ruby-graphviz` you can create images representing your state machines.

`EndState::Graph.new(MyMachine).draw.output png: 'my_machine.png'`

If you use events in your machine, it will add the events along the arrow representing the transition. If you don't want this,
pass in false when contructing the Graph.

`EndState::Graph.new(MyMachine, false).draw.output png: 'my_machine.png'`

## Testing

Included is a custom RSpec matcher for testing your machines.

In your `spec_helper.rb` add:

```ruby
require 'end_state_matchers'
```

In the spec for your state machine:

```ruby
describe Machine do
  specify { expect(Machine).to have_transition(a: :b).with_guard(MyGuard) }
  specify { expect(Machine).to have_transition(a: :b).with_concluder(MyConcluder) }
  specify { expect(Machine).to have_transition(a: :b).with_guard(MyGuard).with_concluder(MyConcluder) }
  specify { expect(Machine).to have_transition(a: :b).with_guards(MyGuard, AnotherGuard) }
  specify { expect(Machine).to have_transition(a: :b).with_concluders(MyConcluder, AnotherConcluder) }
  specify { expect(Machine).not_to have_transition(a: :c) }
end
```

## Contributing

1. Fork it ( https://github.com/Originate/end_state/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
