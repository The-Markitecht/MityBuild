# object-oriented programming framework for Tcl 8.6 and maybe prior versions.

package require MityBuild

proc class {clsName clsBody} {
    # declare a class type containing one or more "var" and/or "method".
    
    # clear out a namespace with the same name as the class, for storing its metadata.
    catch {namespace delete ${clsName}}
    namespace eval $clsName {}
    set ${clsName}::body $clsBody
    
    # define a proc to instantiate object of the class.
    # syntax looks like a .new method of the class itself.
    proc $clsName.new {objName args} "object {$clsName} {$clsBody} \$objName \$args"
}

proc object {clsName clsBody objName ctorArgs} {
    # only for internal use of OOP framework.  instantiates an object of the given class.
    
    # clear out a namespace with the same name as the object, for storing its vars.
    catch {namespace delete ${name}}
    namespace eval $objName {
        set vars [list class]
        set vars2 [list class class]
    }    
    set ${objName}::class $clsName
    
    # define a proc with the same name as the object, for setting/getting its vars.
    interp alias {} $objName {} defaultAccessor $objName
    
    # define a proc for executing arbitrary code.
    #proc $objName {args} "namespace eval $objName \$args"
    
    # define methods of the object.
    set this $objName
    eval $clsBody
    
    # call object ctor, if any.
    if {[llength [info commands $objName.new]]} {
        $objName.new {*}$ctorArgs
    } else {
        # no ctor; just set the given series of variables, if any.
        defaultCtor $ctorArgs 
    }
}

proc defaultAccessor {objName varName args} {
    # provides implicit read/write access to all object vars.
    if { ! [info exists ${objName}::$varName]} {
        error "Variable '[string range $varName 0 31]' not found in class '[set ${objName}::class]'.  Maybe you meant to call a method instead?"
    }
    if {[string range $varName 0 0] eq {_}} {
        error "Variable '[string range $varName 0 31]' in class '[set ${objName}::class]' is private."
    }
    set ${objName}::$varName {*}$args
}

proc inherit {baseClassName} {
    # inherits the methods and variables of the given base class into the current class.
    # overridden base class methods are accessible with syntax 'base.myMethod'. 
    upvar this this
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

set testCode {
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
    puts [lindex [split $errorInfo \n] 0]
    assert {[catch {boo color}]}
    puts [lindex [split $errorInfo \n] 0]

    # test refusing to set/get a private var
    assert {[catch {boo _poop black}]}
    puts [lindex [split $errorInfo \n] 0]
    assert {[catch {boo _poop}]}
    puts [lindex [split $errorInfo \n] 0]

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
    
#TODO: explore any existing support for multiple inheritance.  probly works fine but only memorizes name of final-given base class.

#TODO: re-test without MityBuild?  maybe only the test cases require it.
}

#eval $testCode; exit
