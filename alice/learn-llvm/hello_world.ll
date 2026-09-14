define i32 @foo() {
    %a = add i32 2, 3
    ret i32 %a
}

define void @bar() {
    ret void
}

define i32 @heresnewfunction() {
    ret i32 1
}

define i32 @inst_combine(i32 %a) {
    %b = add i32 %a, 0
    ret i32 %b
}