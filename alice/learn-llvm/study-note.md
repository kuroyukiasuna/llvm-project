## Writing an LLVM pass

https://llvm.org/docs/WritingAnLLVMNewPMPass.html

A pass that inherits from RequiredPassInfoMixin<PassT> is a required pass. For example:
```
class HelloWorldPass : public RequiredPassInfoMixin<HelloWorldPass> {
public:
  PreservedAnalyses run(Function &F, FunctionAnalysisManager &AM);
};
```
A required pass is a pass that may not be skipped. An example of a required pass is AlwaysInlinerPass, which must always be run to preserve alwaysinline semantics. Pass managers are required since they may contain other required passes.

An example of how a pass can be skipped is the optnone function attribute, which specifies that optimizations should not be run on the function. Required passes will still be run on optnone functions.

For more implementation details, see PassInstrumentation::runBeforePass().

LLVM provides a mechanism to register pass plugins within various tools like clang or opt. A pass plugin can add passes to default optimization pipelines or to be manually run via tools like opt.


### Why opt is ignoring your loop
When you ran clang -S -emit-llvm learn-llvm/LICM.c, Clang defaulted to -O0 (No Optimization mode).In modern versions of LLVM, compiling with -O0 causes Clang to tag every function in the resulting .ll file with a special internal attribute called optnone. When the opt tool runs the -passes=licm pass and scans your file, it sees the optnone tag on your LICM function and silently skips it entirely to preserve your exact unoptimized debugging layout.Furthermore, unoptimized -O0 IR forces every variable to constantly load and store from the stack frame (alloca memory locations) instead of using registers. LICM struggles to optimize raw stack memory unless standard clean-up passes run first.How to see LICM in actionTo strip away the optnone block and prepare the IR for manual passes, you must generate your .ll file using the -Xclang -disable-O0-optnone flags. You should also run mem2reg first to move those unoptimized stack operations into clean LLVM registers.


LICM done here:
```
if (CurLoop->hasLoopInvariantOperands(&I) &&
    canSinkOrHoistInst(I, AA, DT, CurLoop, MSSAU, true, Flags, ORE) &&
    isSafeToExecuteUnconditionally(I, DT, TLI, CurLoop, SafetyInfo, ORE,
                                    Preheader->getTerminator(), AC,
                                    AllowSpeculation)) {
  hoist(I, DT, CurLoop, CFH.getOrCreateHoistedBlock(BB), SafetyInfo,
        MSSAU, SE, ORE);
  HoistedInstructions.push_back(&I);
  Changed = true;
  continue;
}
```