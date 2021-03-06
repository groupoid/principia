from __future__ import annotations
from typing import List, Dict, Tuple
from dataclasses import dataclass, field
from sexpdata import Symbol

__all__ = [
    "Name", "Term",
    "Lit", "Var", "Symtree", "Hole",
    "Argument", "Sorry", "Lemma", "Proof",
    "InferenceRule", "State"
]

Name = str

class Term: pass

@dataclass
class Lit(Term):
    name : Name

@dataclass
class Var(Term):
    name : Name

@dataclass
class Symtree(Term):
    children : List[Term]

@dataclass
class Hole(Term):
    pass

def sexpr(τ):
    if isinstance(τ, Lit):
        return τ.name
    elif isinstance(τ, Var):
        return τ.name
    elif isinstance(τ, Symtree):
        return "(%s)" % " ".join(map(sexpr, τ.children))
    elif isinstance(τ, Hole):
        return "_"
    else:
        raise TypeError("this should never happens (naked Term)")
Term.__str__ = sexpr

class Argument: pass

@dataclass
class Sorry(Argument):
    name : str

@dataclass
class Lemma(Argument):
    name : Name

@dataclass
class Proof:
    edge          : Name
    arguments     : List[Argument]
    substitutions : Dict[Name, Term]

@dataclass
class InferenceRule:
    premises   : List[Term]
    conclusion : Term

@dataclass
class State:
    variables : List[Name]                = field(default_factory=list)
    infix     : Dict[Symbol, int]         = field(default_factory=dict)
    context   : Dict[Name, InferenceRule] = field(default_factory=dict)
    bound     : List[Term]                = field(default_factory=list)
    defs      : List[Tuple[Term, Term]]   = field(default_factory=list)