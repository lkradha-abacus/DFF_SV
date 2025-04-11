// Code your design here
module dff(input logic d,clock,reset, output logic q,qbar);
  always_ff@(posedge clock)
    begin
      if(reset)
        begin
          q<=0;
        end
      else
        q<=d;
    end
  assign qbar=~q;
endmodule

interface dff_if(input logic clock);
  logic d;
  logic reset;
  logic q;
  logic qbar;
  
  clocking dff_drv_cb @(posedge clock);
    default input #1 output #1;
    output d;
    output reset;
  endclocking
  
  clocking dff_mon_cb @(posedge clock);
    default input #1 output #1;
    input q;
    input qbar;
  endclocking
  
  modport dff_drv_mp(clocking dff_drv_cb);
    
  modport dff_mon_mp(clocking dff_mon_cb);
 endinterface




class transaction;
  rand logic d;
  rand logic reset;
  logic q;
  logic qbar;
  
  constraint rst{reset dist{0:=80, 1:=20};}
  constraint din{d dist{0:=50, 1:=50};}
  
  function void display(string name);
    $display("[%0s]: reset = %0b: d = %0b: q = %0b: qbar: %0b",name,reset,d,q,qbar);
  endfunction
  
  function transaction copy();
    copy=new();
    copy.d=this.d;
    copy.reset=this.reset;
    copy.q=this.q;
    copy.qbar=this.qbar;
  endfunction
endclass
  
    class generator;
  transaction tr;
  mailbox #(transaction) mbx;
  mailbox #(transaction) mbxref;
  event sconext;
  event done;
  int num_trans=5;
  
  function new(mailbox #(transaction) mbx, mailbox #(transaction) mbxref);
    this.mbx=mbx;
    this.mbxref=mbxref;
    tr=new;
  endfunction
  
  task run();
    repeat(num_trans)begin
      assert(tr.randomize()) else $error("Randomization failed");
      tr.display("Gen");
      mbx.put(tr.copy);
      mbxref.put(tr.copy);
      ->sconext;
    end
    ->done;
  endtask
endclass
    
    class driver;
  transaction tr;
  mailbox #(transaction)mbx;
  virtual dff_if.dff_drv_mp vif;
  
  function new(mailbox #(transaction) mbx, virtual dff_if.dff_drv_mp vif);
    this.vif=vif;
    this.mbx=mbx;
  endfunction
  
  task reset();
        @(vif.dff_drv_cb);
        vif.dff_drv_cb.reset <= 1;
        repeat (2) @(vif.dff_drv_cb);
        vif.dff_drv_cb.reset <= 0;
    endtask
  
  task run();
    forever begin
      @(vif.dff_drv_cb);
      mbx.get(tr);
      vif.dff_drv_cb.d <= tr.d;
      vif.dff_drv_cb.reset <= tr.reset;
      tr.display("DRV");
    end
  endtask 
endclass
           
    class monitor;
  virtual dff_if.dff_mon_mp vif;
  mailbox #(transaction)mbx;
  transaction tr;
  
  function new(mailbox #(transaction) mbx, virtual dff_if.dff_mon_mp vif);
    this.mbx=mbx;
    this.vif=vif;
  endfunction
  
  task run();
    forever begin
      tr=new();
      @(vif.dff_mon_cb);
      @(vif.dff_mon_cb);
      tr.q = vif.dff_mon_cb.q;
      tr.qbar = vif.dff_mon_cb.qbar;
      mbx.put(tr);
      tr.display("MON");
    end
  endtask
endclass
  
    class scoreboard;
  transaction tr;
  transaction trref;
  mailbox #(transaction)mbx;
  mailbox #(transaction)mbxref;
  event sconext;
  
  function new(mailbox #(transaction)mbx, mailbox #(transaction)mbxref);
    this.mbx=mbx;
    this.mbxref=mbxref;
  endfunction
  
  task run();
    forever begin
      mbx.get(tr);
      mbxref.get(trref);
      tr.display("SCO");
      trref.display("REF");
      if(!trref.reset && tr.q==trref.d)
        $display("[SCO]: Data Matched");
      else
        $display("[SCO]: Data Mismatched");
      ->sconext;
    end
  endtask
endclass
      
class environment;
  generator gen;
  driver drv;
  monitor mon;
  scoreboard sco;
  
  mailbox #(transaction) gdmbx;
  mailbox #(transaction) msbmbx;
  mailbox #(transaction) gsbmbx;
  
  virtual dff_if.dff_drv_mp vif_drv;
  virtual dff_if.dff_mon_mp vif_mon;
  
  event next;
  
  function new(virtual dff_if.dff_drv_mp vif_drv, virtual dff_if.dff_mon_mp vif_mon);
    this.vif_mon=vif_mon;
    this.vif_drv=vif_drv;
    gdmbx=new();
    msbmbx=new();
    gsbmbx=new();
    
    gen=new(gdmbx, gsbmbx);
    drv=new(gdmbx, vif_drv);
    mon=new(msbmbx, vif_mon);
    sco=new(msbmbx,gsbmbx);
    
    gen.sconext=next;
    sco.sconext=next;
    
  endfunction
  
  task pre_test();
        drv.reset();
    endtask
  
  task test();
    fork
      gen.run();
      drv.run();
      mon.run();
      sco.run();
    join
  endtask
  
  task post_test;
    wait(gen.done.triggered);
    $finish();
  endtask
  
  task run();
    pre_test();
    test();
    post_test();
  endtask
endclass
        
  
  package dff_pkg;
`include "transaction.sv"
`include "generator.sv"
`include "driver.sv"
`include "monitor.sv"
`include "scoreboard.sv"
`include "environment.sv"

endpackage

// Code your testbench here
// or browse Examples
`include "dff_pkg.sv"
  import dff_pkg::*;
module testbench;
  logic clock;
  
  initial begin
    clock=0;
    forever #5 clock=~clock;
  end
  
  dff_if dff_if_inst(.clock(clock));
  
  dff DUT(.d(dff_if_inst.d), .clock(dff_if_inst.clock), .reset(dff_if_inst.reset), .q(dff_if_inst.q), .qbar(dff_if_inst.qbar));
  
  environment env;

  initial begin
    $dumpfile("dump.vcd");
        $dumpvars;
    env=new(dff_if_inst.dff_drv_mp, dff_if_inst.dff_mon_mp);
    env.run();
    #100; 
    $finish;
  end
endmodule




  