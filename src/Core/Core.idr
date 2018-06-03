module Core.Core

import Core.TT
import Core.CaseTree
import Parser.Support

import public Data.IORef
import public Control.Catchable

public export
data TTCErrorMsg
    = FormatOlder
    | FormatNewer
    | EndOfBuffer String
    | Corrupt String

-- All possible errors
-- 'annot' is an annotation provided by the thing which called the
-- function which had an error; it's intended to provide any useful information
-- a high level language might need, e.g. file/line number
public export
data Error annot
    = Fatal (Error annot) -- flag as unrecoverable (so don't postpone awaiting further info)
    | CantConvert annot (Env Term vars) (Term vars) (Term vars)
    | CantSolveEq annot (Env Term vars) (Term vars) (Term vars)
    | Cycle annot (Env Term vars) (Term vars) (Term vars)
    | WhenUnifying annot (Env Term vars) (Term vars) (Term vars) (Error annot)
    | ValidCase annot (Env Term vars) (Either (Term vars) (Error annot))
    | UndefinedName annot Name
    | InvisibleName annot Name
    | BadTypeConType annot Name 
    | BadDataConType annot Name Name
    | LinearUsed annot Nat Name
    | LinearMisuse annot Name RigCount RigCount
    | AmbiguousName annot (List Name)
    | AmbiguousElab annot (List (Term vars))
    | AllFailed (List (Error annot))
    | InvalidImplicit annot Name (Term vars)
    | CantSolveGoal annot (Env Term vars) (Term vars)
    | UnsolvedHoles (List (annot, Name))
    | SolvedNamedHole annot Name
    | VisibilityError annot Visibility Name Visibility Name
    | NonLinearPattern annot Name
    | BadPattern annot Name
    | NoDeclaration annot Name
    | AlreadyDefined annot Name
    | NotFunctionType annot (Term vars)
    | CaseCompile annot Name CaseError 
    | BadDotPattern annot (Term vars) (Term vars)
    | BadImplicit annot String
    | BadRunElab annot (Term vars)
    | GenericMsg annot String
    | TTCError TTCErrorMsg
    | FileErr String FileError
    | ParseFail ParseError
    | ModuleNotFound annot (List String)
    | CyclicImports (List (List String))
    | InternalError String

    | InType annot Name (Error annot)
    | InCon annot Name (Error annot)
    | InLHS annot Name (Error annot)
    | InRHS annot Name (Error annot)

export
Show TTCErrorMsg where
  show FormatOlder = "TTC data is in an older format"
  show FormatNewer = "TTC data is in a newer format"
  show (EndOfBuffer when) = "End of buffer when reading " ++ when
  show (Corrupt ty) = "Corrupt TTC data for " ++ ty

-- Simplest possible display - higher level languages should unelaborate names
-- and display annotations appropriately
export
Show annot => Show (Error annot) where
  show (Fatal err) = show err
  show (CantConvert fc env x y) 
      = show fc ++ ":Type mismatch: " ++ show x ++ " and " ++ show y
  show (CantSolveEq fc env x y) 
      = show fc ++ ":" ++ show x ++ " and " ++ show y ++ " are not equal"
  show (Cycle fc env x y) 
      = show fc ++ ":Occurs check failed: " ++ show x ++ " and " ++ show y
  show (WhenUnifying fc _ x y err)
      = show fc ++ ":When unifying: " ++ show x ++ " and " ++ show y ++ "\n\t" ++ show err
  show (ValidCase fc _ prob)
      = show fc ++ ":" ++ 
           case prob of
             Left tm => assert_total (show tm) ++ " is not a valid impossible pattern because it typechecks"
             Right err => "Not a valid impossible pattern:\n\t" ++ assert_total (show err)
  show (UndefinedName fc x) = show fc ++ ":Undefined name " ++ show x
  show (InvisibleName fc (NS ns x)) 
       = show fc ++ ":Name " ++ show x ++ " is inaccessible since " ++
         showSep "." (reverse ns) ++ " is not explicitly imported"
  show (BadTypeConType fc n) 
       = show fc ++ ":Return type of " ++ show n ++ " must be Type"
  show (BadDataConType fc n fam) 
       = show fc ++ ":Return type of " ++ show n ++ " must be in " ++ show fam
  show (InvisibleName fc x) = show fc ++ ":Name " ++ show x ++ " is inaccessible since "
  show (LinearUsed fc count n)
      = show fc ++ ":There are " ++ show count ++ " uses of linear name " ++ show n
  show (LinearMisuse fc n exp ctx)
      = show fc ++ ":Trying to use " ++ showRig exp ++ " name " ++ show n ++
                   " in " ++ showRel ctx ++ " context"
     where
       showRig : RigCount -> String
       showRig Rig0 = "irrelevant"
       showRig Rig1 = "linear"
       showRig RigW = "unrestricted"

       showRel : RigCount -> String
       showRel Rig0 = "irrelevant"
       showRel Rig1 = "relevant"
       showRel RigW = "non-linear"

  show (AmbiguousName fc ns) = show fc ++ ":Ambiguous name " ++ show ns
  show (AmbiguousElab fc ts) = show fc ++ ":Ambiguous elaboration " ++ show ts
  show (AllFailed ts) = "No successful elaboration: " ++ assert_total (show ts)
  show (InvalidImplicit fc n tm) 
      = show fc ++ ":" ++ show n ++ " is not a valid implicit argument in " ++ show tm
  show (CantSolveGoal fc env g) 
      = show fc ++ ":Can't solve goal " ++ assert_total (show g)
  show (UnsolvedHoles hs) = "Unsolved holes " ++ show hs
  show (SolvedNamedHole fc h) = show fc ++ ":Named hole " ++ show h ++ " is solved by unification"
  show (VisibilityError fc vx x vy y)
      = show fc ++ ":" ++ show vx ++ " " ++ show x ++ " cannot refer to "
                       ++ show vy ++ " " ++ show y
  show (NonLinearPattern fc n) = show fc ++ ":Non linear pattern variable " ++ show n
  show (BadPattern fc n) = show fc ++ ":Pattern not allowed here: " ++ show n
  show (NoDeclaration fc x) = show fc ++ ":No type declaration for " ++ show x
  show (AlreadyDefined fc x) = show fc ++ ":" ++ show x ++ " is already defined"
  show (NotFunctionType fc tm) = show fc ++ ":Not a function type: " ++ show tm
  show (CaseCompile fc n DifferingArgNumbers) 
      = show fc ++ ":Patterns for " ++ show n ++ " have different numbers of arguments"
  show (CaseCompile fc n DifferingTypes) 
      = show fc ++ ":Patterns for " ++ show n ++ " require matching on different types"
  show (CaseCompile fc n UnknownType) 
      = show fc ++ ":Can't infer type to match in " ++ show n
  show (BadDotPattern fc x y)
      = show fc ++ ":Can't match on " ++ show x
  show (BadImplicit fc str) = show fc ++ ":" ++ str ++ " can't be bound here"
  show (BadRunElab fc script) = show fc ++ ":Bad elaborator script " ++ show script
  show (GenericMsg fc str) = show fc ++ ":" ++ str
  show (TTCError msg) = "Error in TTC file: " ++ show msg
  show (FileErr fname err) = "File error (" ++ fname ++ "): " ++ show err
  show (ParseFail err) = "Parse error (" ++ show err ++ ")"
  show (ModuleNotFound fc ns) 
      = show fc ++ ":" ++ showSep "." (reverse ns) ++ " not found"
  show (CyclicImports ns)
      = "Module imports form a cycle: " ++ showSep " -> " (map showMod ns)
    where
      showMod : List String -> String
      showMod ns = showSep "." (reverse ns)
  show (InternalError str) = "INTERNAL ERROR: " ++ str

  show (InType fc n err)
       = show fc ++ ":When elaborating type of " ++ show n ++ ":\n" ++
         show err
  show (InCon fc n err)
       = show fc ++ ":When elaborating type of constructor " ++ show n ++ ":\n" ++
         show err
  show (InLHS fc n err)
       = show fc ++ ":When elaborating left hand side of " ++ show n ++ ":\n" ++
         show err
  show (InRHS fc n err)
       = show fc ++ ":When elaborating right hand side of " ++ show n ++ ":\n" ++
         show err

export
error : Error annot -> Either (Error annot) a
error = Left

export
record Core annot t where
  constructor MkCore
  runCore : IO (Either (Error annot) t)

export
coreRun : Core annot a -> 
          (Error annot -> IO b) -> (a -> IO b) -> IO b
coreRun (MkCore act) err ok = either err ok !act

export
coreFail : Error annot -> Core annot a
coreFail e = MkCore $ pure (Left e)

export
wrapError : (Error annot -> Error annot) -> Core annot a -> Core annot a
wrapError fe (MkCore prog)
    = MkCore $ prog >>=
         (\x => case x of
                     Left err => pure (Left (fe err))
                     Right val => pure (Right val))

-- This would be better if we restrict it to a limited set of IO operations
export
%inline
coreLift : IO a -> Core annot a
coreLift op = MkCore $ map Right op

{- Monad, Applicative, Traversable are specialised by hand for Core.
In theory, this shouldn't be necessary, but it turns out that Idris 1 doesn't
specialise interfaces under 'case' expressions, and this has a significant
impact on both compile time and run time. 

Of course it would be a good idea to fix this in Idris, but it's not an urgent
thing on the road to self hosting, and we can make sure this isn't a problem
in the next version (i.e., in this project...)! -}

-- Monad (specialised)
export %inline
(>>=) : Core annot a -> (a -> Core annot b) -> Core annot b
(>>=) (MkCore act) f 
    = MkCore $ act >>= 
         (\x => case x of
                     Left err => pure (Left err)
                     Right val => runCore (f val))

-- Applicative (specialised)
export %inline
pure : a -> Core annot a
pure x = MkCore (pure (pure x))

export
(<*>) : Core annot (a -> b) -> Core annot a -> Core annot b
(<*>) (MkCore f) (MkCore a) = MkCore [| f <*> a |]

export %inline
when : Bool -> Lazy (Core annot ()) -> Core annot ()
when True f = f
when False f = pure ()

export
Catchable (Core annot) (Error annot) where
  catch (MkCore prog) h 
      = MkCore (do p' <- prog
                   case p' of
                        Left e => let MkCore he = h e in he
                        Right val => pure (Right val))
  throw = coreFail

-- Traversable (specialised)
export
traverse : (a -> Core annot b) -> List a -> Core annot (List b)
traverse f [] = pure []
traverse f (x :: xs) = pure $ !(f x) :: !(traverse f xs)

export
data Ref : label -> Type -> Type where
	   MkRef : IORef a -> Ref x a

export
newRef : (x : label) -> t -> Core annot (Ref x t)
newRef x val 
    = do ref <- coreLift (newIORef val)
         pure (MkRef ref)

export %inline 
get : (x : label) -> {auto ref : Ref x a} -> Core annot a
get x {ref = MkRef io} = coreLift (readIORef io)

export %inline
put : (x : label) -> {auto ref : Ref x a} -> a -> Core annot ()
put x {ref = MkRef io} val = coreLift (writeIORef io val)


