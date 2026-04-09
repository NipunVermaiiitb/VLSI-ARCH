module Stage2PreAdderCPA(
    input  [111:0] partial_products_sum,
    input  [111:0] partial_products_carry,
    output [111:0] sum
);

    assign sum = partial_products_sum + partial_products_carry;

endmodule
