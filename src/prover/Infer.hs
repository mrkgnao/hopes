module Infer where

import Hopl
import Subst
import Logic

import Types  (Type, order)
import Syntax (HpSymbol(..))

import Control.Monad.Reader
import Control.Monad.State
import Control.Monad.Identity

import List (nub)


type Infer a = ReaderT (Prog a) (StateT Int (LogicT Identity))

runInfer p m = runIdentity $ runLogic Nothing $ evalStateT (runReaderT m p) 0


-- try prove a formula by refutation
-- prove  :: Goal a -> Infer a (Subst a)
prove g =  do
    ans <- refute g
    return (restrict (concatMap flexs g) ans)

-- do a refutation
-- refute :: Goal a -> Infer a (Subst a)
refute [] = return success
refute g = 
    derive g >>- \(g',  s)  ->
    refute (map (subst s) g') >>- \ans ->
    return (s `combine` ans)

-- a derivation
-- derive :: Goal a -> Infer a (Goal a, Subst a)
derive [] = return ([], success)
derive g = 
    let f a = case a of
                 (App (Rigid _) _) -> resolvR a
                 (App (Flex _)  _) -> resolvF a
                 (App (Set _ _) _) -> resolvS a
                 _ -> fail "Cannot derive anything from that atom"
    in
    split g  >>- \(a, g') ->
    f a      >>- \(g'', s) ->
    return (g'' ++ g', s)



-- derive by resolution (the common rigid case)
-- FIXME: clause assumed to be a tuple.
--        goal assumed to be equivalent to the body of a clause
-- resolv :: Expr a -> Infer a (Goal a, Subst a)
resolvR e = 
    clausesOf e >>- \c     ->
    variant c   >>- \(h,b) ->
    unify e h   >>- \s     ->
    return (b, s)


resolvF (App (Flex v) es) = resolvS (App (Set [] v) es)


resolvS (App (Set ss v) e) = do
    x  <- freshIt v
    v' <- freshIt v
    (Flex x) `waybelow` e >>- \s ->
        return ([], (bind v (Set [(Flex x)] v')) `combine` s)


-- unification

unify :: (Eq a, Monad m) => Expr a -> Expr a -> m (Subst a)

unify (Flex v1) e@(Flex v2)
    | v1 == v2  = return success
    | otherwise = return (bind v1 e)

unify (Flex v) t = do
    occurCheck v t
    return (bind v t)

unify t1 t2@(Flex v) = unify t2 t1

unify (App e1 e2) (App e1' e2') = do
    s1 <- unify e1 e1'
    s2 <- unify (subst s1 e2) (subst s1 e2')
    return (s1 `combine` s2)

unify (Tup es) (Tup es') = listUnify es es'

unify (Rigid p) (Rigid q)
    | p == q    = return success
    | otherwise = fail "Unification fail"

unify _ _ = fail "Should not happen"


listUnify  :: (Eq a, Monad m) => [Expr a] -> [Expr a] -> m (Subst a)
listUnify [] [] = return success
listUnify (e1:es1) (e2:es2) = do
    s <- unify e1 e2
    s' <- listUnify (map (subst s) es1) (map (subst s) es2)
    return (s `combine` s')

listUnify _ _   = fail "lists of different length"

occurCheck :: (Eq a, Monad m) => a -> Expr a -> m ()
occurCheck a e = when (a `occursIn` e) $ fail "Occur Check"

occursIn a e = a `elem` (flexs e)


{-
    (waybelow x y) successed with a substitution if x is waybelow of y
    waybelow can successed more than once e.g. for all x that are waybelow y
    waybelow fails if no substitution exists to make x waybelow y
-}
-- waybelow :: MonadLogic m => Expr a -> Expr a -> m Subst
-- if p is higher order we want a finitary subset S
-- if p is zero order just unify x with p


waybelow (Flex x) (Rigid p@(_,t))
    | order t == 0 = unify (Flex x) (Rigid p)
    | otherwise    = error "last to implement"
        -- prove (p(X1, ..., XN)) = [s1, s2, ...]

-- possibly a function symbol application (remember no partial applications allowed, so that can't be higher order)
waybelow e1@(Flex _) e2@(App _ _) = unify e1 e2

waybelow e@(Flex x) (Set sl v) = do
    v' <- freshIt v
    return $ bind v (Set [e] v')

waybelow e1@(Flex _) e2@(Flex v@(_, t))
    | order t == 0 = unify e1 e2
    | otherwise    = waybelow e1 (Set [] v)

waybelow (Flex x) e@(Tup es) = do
    xs <- mapM (\e -> freshIt x) es
    let xs' = Tup (map Flex xs)
    s <- waybelow xs' e
    return $ combine (bind x xs') s

waybelow (Tup es) (Tup es') = do
    ss <- zipWithM waybelow es es'
    return (foldl combine success ss)

-- can't go in this case. Defined just for completeness.
waybelow (Rigid p) (Rigid q) 
    | p == q    = return success -- same intensions -> same extensions
    | otherwise = fail "cannot compute if one rigid symbol is waybelow of some other rigid symbol"


-- utils

-- split a goal to an atom and the rest goal
-- deterministic computation picking always the left-most atom
split :: Goal a -> Infer a (Expr a, Goal a)
split []     = fail "Empty goal. Can't pick an atom"
split (x:xs) = return (x, xs)

clausesOf (App q _) = do
    p <- ask
    let cl = filter (\(App r _, b)-> r == q) p
    msum (map return cl)

-- make a fresh variant of a clause.
-- monadic computation because of freshVar.
-- variant :: Clause a -> Infer a (Clause a)
-- FIXME: subst assumed to be list 
-- PITFALL: flexs are computed every time
variant (h,b) =
    let vs = nub $ flexs h ++ concatMap flexs b
        bindWithFresh v = do
            v' <- freshIt v
            return (v, Flex v')
    in do
    s <- mapM bindWithFresh vs
    return (subst s h, map (subst s) b)

freshIt :: MonadState Int m => (HpSymbol, Type) -> m (HpSymbol, Type)
freshIt (_, ty) = do
    a' <- get
    modify (+1)
    return $ (Sym ("_V" ++ show a'), ty)