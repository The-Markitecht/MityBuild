# object-oriented programming framework for Tcl 8.6 and maybe prior versions.

package require MityBuild

rename ::unknown ::oopOldUnknown
proc ::unknown {args} {
    set parts [split [lindex $args 0] . ]
    if {[llength $parts] > 1} {
        
    }
    ::oopOldUnknown {*}$args
}

proc class {clsName clsBody} {
    # declare a class type containing one or more "var" and/or "method".
    
    # clear out a namespace with the same name as the class, for storing its metadata.
    catch {namespace delete ${clsName}}
    namespace eval $clsName {}
    set ${clsName}::body $clsBody
    set ${clsName}::template [dict create class $clsName]
    
    # define methods of the object.
    eval $clsBody

    # define a proc to instantiate object of the class.
    # syntax looks like a .new method of the class itself.
    proc ${clsName}::new {objName args} "newObject {$clsName} \$objName \$args"
}

proc newObject {clsName objName ctorArgs} {
    # only for internal use of OOP framework.  instantiates an object of the given class.
    
    upvar 2 $objName this
    set this [set ${clsName}::template]
    
    # call object ctor, if any.
    if {[llength [info commands ${clsName}::ctor]]} {
        ${clsName}::ctor {*}$ctorArgs
    } else {
        # no ctor; just set the given series of variables, if any.
        set this [dict replace $this {*}$ctorArgs]
    }
    return $objName
}

proc inherit {baseClassName} {
    # inherits the methods and variables of the given base class into the current class.
    # overridden base class methods are accessible with syntax 'base.myMethod'. 
    eval [set ${baseClassName}::body]
    var baseClass $baseClassName
}

proc var {varName {value {}}} {
    # declare an instance variable that will be directly readable & writable
    # as a local in all method bodies. 
    upvar 1 this this
    lappend ${this}::vars $varName
    lappend ${this}::vars2 $varName $varName
    set ${this}::$varName $value
}

proc method {methodName argList body} {
    # declare a proc that has direct access to object vars as locals,
    # and also direct undecorated access to other methods of the object.
    # call the method using syntax:
    #   'myMethod' from the body of another method of the same object instance.
    #   'myObject.myMethod' from outside the object.
    #       or 'myObject::myMethod'.
    upvar 1 this this
    if {[llength [info commands ${this}::$methodName]]} {
        catch {rename ${this}::base.$methodName {} }
        rename ${this}::$methodName ${this}::base.$methodName
    }
    proc ${this}::$methodName $argList "
        set this {$this}
        namespace upvar [namespace current]$this {*}\$${this}::vars2
        $body
    "
    interp alias {} $this.$methodName {} ${this}::$methodName
}

proc defaultCtor {ctorArgs} {
    # just set the given series of variables, if any.
    # this can be called by the explicit ctor if desired.
    upvar this this
    foreach {n v} $ctorArgs {
        $this $n $v
    }        
}

proc dumpNs {ns indent} {
    vars = [info vars ${ns}::tot]
    if {[llength $vars]} {
        puts "$indent$ns"
        foreach v [info vars ${ns}::tot] {
            puts "$indent    *$v"
        }
    }
    foreach ch [namespace children $ns] {
        dumpNs $ch "$indent    "
    }
}

proc testCode {} {
    namespace eval nsTest {
        variable a 5
        proc m1 {} {
            namespace upvar ::nsTest a a
            puts $a
            incr a
        }
        proc m2 {} {
            m1
            m1
            m1
        }
    }
    nsTest::m2
    
    class Pet {
        var color black
        var species
        var age

        method new {species_ color_} {
            puts "before ctor: color $color age $age"
            assert {$color eq {black}}
            assert {$age eq {}}
            species = $species_
            color = $color_
            age = 5
        }        

        method txt {} {
            return "$class $this is a $color $species."
        }
        
        method older {} {
            return [incr age]
        }
        
        method makeTag {} {
            return [txt]
        }
    }

    # test ctor and its parms.
    Pet.new merlin cat white
    # test method can read vars.
    puts [merlin.txt]
    assert {[merlin.txt] eq {Pet merlin is a white cat.}}
    # test method can modify vars.  this was already tested once, in the ctor.
    puts "[merlin.older] [merlin.older] [merlin.older]"
    assert {[merlin.older] == 9}
    # test default setter and getter.
    merlin species devil
    puts [merlin.txt]
    assert {[merlin species] eq {devil}}
    # test a method calling another method.
    assert {[merlin.makeTag] eq {Pet merlin is a white devil.}}

    # test default behavior without ctor.
    class Snake {
        var length
        var _poop stinky
    }
    Snake.new boo length 16
    puts "length [boo length]"
    
    # test refusing to set/get a nonexistent var
    assert {[catch {boo color black}]}
    puts [lindex [split $::errorInfo \n] 0]
    assert {[catch {boo color}]}
    puts [lindex [split $::errorInfo \n] 0]

    # test refusing to set/get a private var
    assert {[catch {boo _poop black}]}
    puts [lindex [split $::errorInfo \n] 0]
    assert {[catch {boo _poop}]}
    puts [lindex [split $::errorInfo \n] 0]

    # test inheritance of vars and methods, including 'new'.
    class Dog {
        inherit Pet
        var coat fuzzy
        method new {species_ color_ coat_} {
            base.new $species_ $color_
            coat = $coat_
        }
        method txt {} {
            older
            return "[base.txt] with coat $coat."
        }
        method polymorphic {} {
            return [txt]
        }
    }
    Dog.new tipper BullChow brown short
    assert {[tipper baseClass] eq {Pet}}
    assert {[tipper coat] eq {short}}
    assert {[tipper age] == 5}
    puts "[tipper.older] [tipper.older]"
    assert {[tipper age] == 7}
    puts [tipper.txt]
    assert {[tipper.txt] eq {Dog tipper is a brown BullChow. with coat short.}}
    assert {[tipper age] == 9}
    assert {[tipper.polymorphic] eq {Dog tipper is a brown BullChow. with coat short.}}

    # test re-use of an object name.
    class Sum {
        var tot 0
        method add {v} {
            tot := ($tot + $v) % 255
        }
    }
    for {set i 0} {$i < 3} {incr i} {
        Sum.new sum
        sum.add 5
        sum.add 5
        sum.add 5
        assert {[sum tot] == 15}
    }    

    # test scope and lifetime of a local object.
    proc locals {} {
        Snake.new slinky length 10
        assert {[namespace exists slinky]}
        assert {[llength [info commands slinky]]}
        assert {[slinky length] == 10}
    }
    locals
    assert { ! [namespace exists slinky]}
    assert { ! [llength [info commands slinky]]}
    
    # test method call on nested object.
    class House {
        var rooms
    }
    class Room {
        var lights
    }
    cora = [House rooms [dict create \
        kitchen [Room lights off] \
        lizzie [Room lights on]]]
    [cora.rooms @ lizzie].lights off
    # wow, that's complex to implement.  and that's just one simple variation.
}

testCode; exit

TODO = {
fix difficulties around composing objects into graphs.  awkward to create,
to assign, and to call.

fix difficulties around object scope.  objects created
in procs are not local; they're global, and visible outside the proc.  they can clash with
names of others outside the proc.  

fix difficulties around object lifetime.  objects created
in procs live on after the proc ends, resulting
in a resource leak (using dynamic name each call) or the need to destroy & recreate in 
each call (using fixed name).  other issues too.
    
explore any existing support for multiple inheritance.  probly works fine but only memorizes name of final-given base class.

re-test without MityBuild?  maybe only the test cases require it.
}
