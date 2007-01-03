{
module Parser where

import Lexer
import HpSyn
import Types
import Utils
import ParseUtils
import Control.Monad.State

}

%tokentype { (Located Token) }
%token 
      ':-'      { (L _ TKgets)   }
      '.'       { (L _ TKdot)    }
      ','       { (L _ TKcomma)  }
      '('       { (L _ TKoparen) }
      ')'       { (L _ TKcparen) }
      '['       { (L _ TKobrak ) }
      '{'       { (L _ TKocurly) }
      '}'       { (L _ TKccurly) }
      ']'       { (L _ TKcbrak ) }
      '|'       { (L _ TKvert )  }
      '_'       { (L _ TKwild )  }
      ID        { (L _ (TKid   $$)) }

%monad { Parser } { >>= } { return }
%lexer { lexer } { (L _ TKEOF) }
%name parseProg  prog
%name parseGoal  goal
%lexer { lexer  } { (L _ TKEOF) }
%monad { Parser } { >>= } { return }

%right '->'
%left '::'
%left ID

%% 

src :: { HpSource }
    : stmts                     { mkSrc (reverse $1) }

stmt :: { LHpStmt }
     : clause                   { L (getLoc $1)     $ HpCl $1 }
     | tysig                    { L (getLoc $1)     $ HpTS $1 }

stmts :: { [LHpStmt] }
      : stmts stmt              { $2:$1 }
      |                         { [] }

clause :: { LHpClause }
       : rule                   { $1 }
       | fact                   { $1 }

clauses :: { [LHpClause] }
        : clauses clause        { $2:$1 }
        |                       { [] }

fact :: { LHpClause }
     : atom '.'                 { L (combLoc $1 $>) $ HpClaus $1 [] }

rule :: { LHpClause }
     : atom ':-' body '.'       { L (combLoc $1 $>) $ HpClaus $1 $3 }

term :: { HoTerm }
     : ID                    { if isVar $1 then HoVar $1 else if (all isDigit $1) then homkNum ((read $1)::Int) else HoConst $1 }
     | '_'                   { HoVar "_" }
     | ID '(' terms ')'      { HoFun $1 (reverse $3) }
     | '[' ']'               { hoEmptyList }
     | '[' terms ']'         { homkList (reverse (hoEmptyList:$2)) }
     | '[' terms '|' term ']' { homkList (reverse ($4:$2)) }

conj :: { [LHpAtom] }
     : conj ',' atom            { $3:$1 }
     | atom                     { [$1] }

atom :: { LHpAtom }
     : exp                      { L (getLoc $1)     $ HpAtom $1 }
     | '!'                      { L (getLoc $1)     $ HpCut }

exp  :: { LHpExpr }
     : '(' exp ')'              { L (combLoc $1 $>) $ HpPar  $2 }
     | exp tyann                { L (combLoc $1 $>) $ HpAnno $1 (unLoc $2) }
     | ID                       { L (getLoc $1)     $ HpPred (getName $1) }
     | exp '(' exps2 ')'        { L (combLoc $1 $>) $ HpApp $1 (reverse $3) }
--     | exp ID exp               { L (combLoc $1 $>) $ HpApp (HpPred (getName $2)) ($1:$3:[])  }

exp2 :: { LHpExpr }
     : term                     { L (getLoc $1)     $ HpTerm $1 }
     | '(' exp2 ')'             { L (combLoc $1 $>) $ HpPar  $2 }
     | exp2 tyann               { L (combLoc $1 $2) $ HpAnno $1 (unLoc $2) }

exps2 :: { [LHpExpr] }
     : exps2 ',' exp2           { $3:$1 }
     | exp2                     { [$1] }

term :: { LHpTerm }
     : ID                       { L (getLoc $1)     $ HpId (getName $1) }
     | '_'                      { L (getLoc $1)     $ HpWild }
     | ID '(' terms ')'         { L (combLoc $1 $>) $ HpFun (getName $1) (reverse $3) }
     | '(' terms2 ')'           { L (combLoc $1 $>) $ HpTup (reverse $2) }
     | '[' ']'                  { L (combLoc $1 $>) $ HpList []           Nothing   }
     | '[' terms ']'            { L (combLoc $1 $>) $ HpList (reverse $2) Nothing   }
     | '[' terms '|' term ']'   { L (combLoc $1 $>) $ HpList (reverse $2) (Just $4) }
     | '{' '}'                  { L (combLoc $1 $>) $ HpSet [] }
     | '{' terms '}'            { L (combLoc $1 $>) $ HpSet $2 }

terms :: { [LHpTerm] }
      : terms ',' term          { $3:$1 }
      | term                    { [$1] }

terms2 :: { [LHpTerm] }
       : terms2 ',' term        { $3:$1 }
       | term ',' term          { $3:$1:[] }

goal :: { HpGoal }
     : conj                     { reverse $1 }

type :: { LHpType }
     : ID                       { L (getLoc $1)     $ HpTyGrd (getName $1) }
     | type '->' type           { L (combLoc $1 $>) $ HpTyFun $1 $3 }
     | '(' types ')'            { L (combLoc $1 $>) $ HpTyTup (reverse $2) }
     | '{' type '}'             { L (combLoc $1 $>) $ HpTyRel $2 }

types :: {  [LHpType]  }
      : types ',' type          { $3:$1 }
      | type                    { [$1]  }

tysig :: { LHpTySign }
      : ID '/' ID tyann         { L (combLoc $1 $>) $ HpTySig (getName $1) (unLoc $4) }

tyann :: { Located Type }
      : '::' type               {% mkTyp $2 >>= \t -> return (L (combLoc $1 $>) t) }

{
happyError = do
    tok <- gets cur_tok
    case unLoc tok of
        TKEOF -> parseError (spanBegin $ getLoc tok) (text "unexpected end of input")
        _     -> parseError (spanBegin $ getLoc tok) (sep [ text "parse error on input", quotes (ppr (unLoc tok)) ])
}