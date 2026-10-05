// Corrected ICS55 inverting 2:1 mux models.
//
// The PDK verilog model for these cells is
//     udp_mux2 u0(Y, A, B, S0);
//     not      u1(Y, Y);          // Y = ~Y : self-referencing
// which is contradictory (the UDP is non-inverting and the not gate
// takes Y as its own input), so any zero-delay simulator either yields
// X or fails to converge.  The liberty function is
//     Y = (!A * !S0) + (!B * S0)
// i.e. an inverting 2:1 mux, which is what these models implement.

module MUXI2X0P5H7L (Y, A, B, S0);
  output Y;
  input A, B, S0;
  assign Y = ~(S0 ? B : A);
endmodule

module MUXI2X0P5H7R (Y, A, B, S0);
  output Y;
  input A, B, S0;
  assign Y = ~(S0 ? B : A);
endmodule

module MUXI2X0P7H7L (Y, A, B, S0);
  output Y;
  input A, B, S0;
  assign Y = ~(S0 ? B : A);
endmodule

module MUXI2X0P7H7R (Y, A, B, S0);
  output Y;
  input A, B, S0;
  assign Y = ~(S0 ? B : A);
endmodule

module MUXI2X1H7L (Y, A, B, S0);
  output Y;
  input A, B, S0;
  assign Y = ~(S0 ? B : A);
endmodule

module MUXI2X1H7R (Y, A, B, S0);
  output Y;
  input A, B, S0;
  assign Y = ~(S0 ? B : A);
endmodule

module MUXI2X1P4H7L (Y, A, B, S0);
  output Y;
  input A, B, S0;
  assign Y = ~(S0 ? B : A);
endmodule

module MUXI2X1P4H7R (Y, A, B, S0);
  output Y;
  input A, B, S0;
  assign Y = ~(S0 ? B : A);
endmodule

module MUXI2X2H7L (Y, A, B, S0);
  output Y;
  input A, B, S0;
  assign Y = ~(S0 ? B : A);
endmodule

module MUXI2X2H7R (Y, A, B, S0);
  output Y;
  input A, B, S0;
  assign Y = ~(S0 ? B : A);
endmodule

module MUXI2X3H7L (Y, A, B, S0);
  output Y;
  input A, B, S0;
  assign Y = ~(S0 ? B : A);
endmodule

module MUXI2X3H7R (Y, A, B, S0);
  output Y;
  input A, B, S0;
  assign Y = ~(S0 ? B : A);
endmodule

module MUXI2X4H7L (Y, A, B, S0);
  output Y;
  input A, B, S0;
  assign Y = ~(S0 ? B : A);
endmodule

module MUXI2X4H7R (Y, A, B, S0);
  output Y;
  input A, B, S0;
  assign Y = ~(S0 ? B : A);
endmodule
