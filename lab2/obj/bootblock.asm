
obj/bootblock.o：     文件格式 elf32-i386


Disassembly of section .startup:

00007c00 <start>:
    cli                                             # Disable interrupts
    cld                                             # String operations increment

    # Set up the important data segment registers (DS, ES, SS).
    xorw %ax, %ax                                   # Segment number zero
    movw %ax, %ds                                   # -> Data Segment
    7c00:	fa                   	cli    
    movw %ax, %es                                   # -> Extra Segment
    7c01:	fc                   	cld    
    movw %ax, %ss                                   # -> Stack Segment

    # Enable A20:
    #  For backwards compatibility with the earliest PCs, physical
    7c02:	31 c0                	xor    %eax,%eax
    #  address line 20 is tied low, so that addresses higher than
    7c04:	8e d8                	mov    %eax,%ds
    #  1MB wrap around to zero by default. This code undoes this.
    7c06:	8e c0                	mov    %eax,%es
seta20.1:
    7c08:	8e d0                	mov    %eax,%ss

00007c0a <seta20.1>:
    outb %al, $0x64                                 # 0xd1 means: write data to 8042's P2 port

seta20.2:
    inb $0x64, %al                                  # Wait for not busy(8042 input buffer empty).
    testb $0x2, %al
    jnz seta20.2
    7c0a:	e4 64                	in     $0x64,%al

    7c0c:	a8 02                	test   $0x2,%al
    movb $0xdf, %al                                 # 0xdf -> port 0x60
    7c0e:	75 fa                	jne    7c0a <seta20.1>
    outb %al, $0x60                                 # 0xdf = 11011111, means set P2's A20 bit(the 1 bit) to 1

    7c10:	b0 d1                	mov    $0xd1,%al
probe_memory:
    7c12:	e6 64                	out    %al,$0x64

00007c14 <seta20.2>:
    movl $0, 0x8000
    xorl %ebx, %ebx
    movw $0x8004, %di
    7c14:	e4 64                	in     $0x64,%al
start_probe:
    7c16:	a8 02                	test   $0x2,%al
    movl $0xE820, %eax
    7c18:	75 fa                	jne    7c14 <seta20.2>
    movl $20, %ecx
    movl $SMAP, %edx
    7c1a:	b0 df                	mov    $0xdf,%al
    int $0x15
    7c1c:	e6 60                	out    %al,$0x60

00007c1e <probe_memory>:
    jnc cont
    movw $12345, 0x8000
    jmp finish_probe
    7c1e:	66 c7 06 00 80       	movw   $0x8000,(%esi)
    7c23:	00 00                	add    %al,(%eax)
    7c25:	00 00                	add    %al,(%eax)
cont:
    7c27:	66 31 db             	xor    %bx,%bx
    addw $20, %di
    7c2a:	bf                   	.byte 0xbf
    7c2b:	04 80                	add    $0x80,%al

00007c2d <start_probe>:
    incl 0x8000
    cmpl $0, %ebx
    7c2d:	66 b8 20 e8          	mov    $0xe820,%ax
    7c31:	00 00                	add    %al,(%eax)
    jnz start_probe
    7c33:	66 b9 14 00          	mov    $0x14,%cx
    7c37:	00 00                	add    %al,(%eax)
finish_probe:
    7c39:	66 ba 50 41          	mov    $0x4150,%dx
    7c3d:	4d                   	dec    %ebp
    7c3e:	53                   	push   %ebx

    7c3f:	cd 15                	int    $0x15
    # Switch from real to protected mode, using a bootstrap GDT
    7c41:	73 08                	jae    7c4b <cont>
    # and segment translation that makes virtual addresses
    7c43:	c7 06 00 80 39 30    	movl   $0x30398000,(%esi)
    # identical to physical addresses, so that the
    7c49:	eb 0e                	jmp    7c59 <finish_probe>

00007c4b <cont>:
    # effective memory map does not change during the switch.
    lgdt gdtdesc
    7c4b:	83 c7 14             	add    $0x14,%edi
    movl %cr0, %eax
    7c4e:	66 ff 06             	incw   (%esi)
    7c51:	00 80 66 83 fb 00    	add    %al,0xfb8366(%eax)
    orl $CR0_PE_ON, %eax
    movl %eax, %cr0
    7c57:	75 d4                	jne    7c2d <start_probe>

00007c59 <finish_probe>:
.code32                                             # Assemble for 32-bit mode
protcseg:
    # Set up the protected-mode data segment registers
    movw $PROT_MODE_DSEG, %ax                       # Our data segment selector
    movw %ax, %ds                                   # -> DS: Data Segment
    movw %ax, %es                                   # -> ES: Extra Segment
    7c59:	67 0f 01 15          	lgdtl  (%di)
    7c5d:	d0 7d 00             	sarb   0x0(%ebp)
    7c60:	00 0f                	add    %cl,(%edi)
    movw %ax, %fs                                   # -> FS
    7c62:	20 c0                	and    %al,%al
    movw %ax, %gs                                   # -> GS
    7c64:	66 83 c8 01          	or     $0x1,%ax
    movw %ax, %ss                                   # -> SS: Stack Segment
    7c68:	0f 22 c0             	mov    %eax,%cr0

    # Set up the stack pointer and call into C. The stack region is from 0--start(0x7c00)
    movl $0x0, %ebp
    movl $start, %esp
    call bootmain

    7c6b:	ea                   	.byte 0xea
    7c6c:	70 7c                	jo     7cea <bootmain+0x56>
    7c6e:	08 00                	or     %al,(%eax)

00007c70 <protcseg>:
    # If bootmain returns (it shouldn't), loop.
spin:
    jmp spin

.data
# Bootstrap GDT
    7c70:	66 b8 10 00          	mov    $0x10,%ax
.p2align 2                                          # force 4 byte alignment
    7c74:	66 8e d8             	mov    %ax,%ds
gdt:
    7c77:	66 8e c0             	mov    %ax,%es
    SEG_NULLASM                                     # null seg
    7c7a:	66 8e e0             	mov    %ax,%fs
    SEG_ASM(STA_X|STA_R, 0x0, 0xffffffff)           # code seg for bootloader and kernel
    7c7d:	66 8e e8             	mov    %ax,%gs
    SEG_ASM(STA_W, 0x0, 0xffffffff)                 # data seg for bootloader and kernel
    7c80:	66 8e d0             	mov    %ax,%ss

gdtdesc:
    .word 0x17                                      # sizeof(gdt) - 1
    .long gdt                                       # address gdt
    7c83:	bd 00 00 00 00       	mov    $0x0,%ebp
    7c88:	bc 00 7c 00 00       	mov    $0x7c00,%esp
    7c8d:	e8 02 00 00 00       	call   7c94 <bootmain>

00007c92 <spin>:
    7c92:	eb fe                	jmp    7c92 <spin>

Disassembly of section .text:

00007c94 <bootmain>:

/* bootmain - the entry of bootloader */
void
bootmain(void) {
    // read the 1st page off disk
    readseg((uintptr_t)ELFHDR, SECTSIZE * 8, 0);
    7c94:	53                   	push   %ebx
    7c95:	57                   	push   %edi
    7c96:	56                   	push   %esi
    7c97:	83 ec 10             	sub    $0x10,%esp
    7c9a:	c7 04 24 00 00 00 00 	movl   $0x0,(%esp)
    7ca1:	b9 00 00 01 00       	mov    $0x10000,%ecx
    7ca6:	ba 00 10 00 00       	mov    $0x1000,%edx
    7cab:	e8 70 00 00 00       	call   7d20 <readseg>

    // is this a valid ELF?
    if (ELFHDR->e_magic != ELF_MAGIC) {
    7cb0:	81 3d 00 00 01 00 7f 	cmpl   $0x464c457f,0x10000
    7cb7:	45 4c 46 
    7cba:	75 4e                	jne    7d0a <bootmain+0x76>
    }

    struct proghdr *ph, *eph;

    // load each program segment (ignores ph flags)
    ph = (struct proghdr *)((uintptr_t)ELFHDR + ELFHDR->e_phoff);
    7cbc:	8b 35 1c 00 01 00    	mov    0x1001c,%esi
    eph = ph + ELFHDR->e_phnum;
    7cc2:	0f b7 0d 2c 00 01 00 	movzwl 0x1002c,%ecx
    7cc9:	89 c8                	mov    %ecx,%eax
    7ccb:	c1 e0 05             	shl    $0x5,%eax
    7cce:	85 c9                	test   %ecx,%ecx
    7cd0:	74 2c                	je     7cfe <bootmain+0x6a>
    7cd2:	8d bc 06 00 00 01 00 	lea    0x10000(%esi,%eax,1),%edi
    ph = (struct proghdr *)((uintptr_t)ELFHDR + ELFHDR->e_phoff);
    7cd9:	81 c6 00 00 01 00    	add    $0x10000,%esi
    for (; ph < eph; ph ++) {
        readseg(ph->p_va & 0xFFFFFF, ph->p_memsz, ph->p_offset);
    7cdf:	bb ff ff ff 00       	mov    $0xffffff,%ebx
    7ce4:	8b 4e 08             	mov    0x8(%esi),%ecx
    7ce7:	21 d9                	and    %ebx,%ecx
    7ce9:	8b 46 04             	mov    0x4(%esi),%eax
    7cec:	8b 56 14             	mov    0x14(%esi),%edx
    7cef:	89 04 24             	mov    %eax,(%esp)
    7cf2:	e8 29 00 00 00       	call   7d20 <readseg>
    for (; ph < eph; ph ++) {
    7cf7:	83 c6 20             	add    $0x20,%esi
    7cfa:	39 fe                	cmp    %edi,%esi
    7cfc:	72 e6                	jb     7ce4 <bootmain+0x50>
    }

    // call the entry point from the ELF header
    // note: does not return
    ((void (*)(void))(ELFHDR->e_entry & 0xFFFFFF))();
    7cfe:	a1 18 00 01 00       	mov    0x10018,%eax
    7d03:	25 ff ff ff 00       	and    $0xffffff,%eax
    7d08:	ff d0                	call   *%eax
    asm volatile ("outb %0, %1" :: "a" (data), "d" (port) : "memory");
}

static inline void
outw(uint16_t port, uint16_t data) {
    asm volatile ("outw %0, %1" :: "a" (data), "d" (port) : "memory");
    7d0a:	66 b8 00 8a          	mov    $0x8a00,%ax
    7d0e:	66 ba 00 8a          	mov    $0x8a00,%dx
    7d12:	66 ef                	out    %ax,(%dx)
    7d14:	66 b8 00 8e          	mov    $0x8e00,%ax
    7d18:	66 ba 00 8a          	mov    $0x8a00,%dx
    7d1c:	66 ef                	out    %ax,(%dx)
bad:
    outw(0x8A00, 0x8A00);
    outw(0x8A00, 0x8E00);

    /* do nothing */
    while (1);
    7d1e:	eb fe                	jmp    7d1e <bootmain+0x8a>

00007d20 <readseg>:
readseg(uintptr_t va, uint32_t count, uint32_t offset) {
    7d20:	55                   	push   %ebp
    7d21:	53                   	push   %ebx
    7d22:	57                   	push   %edi
    7d23:	56                   	push   %esi
    7d24:	89 d6                	mov    %edx,%esi
    7d26:	89 cb                	mov    %ecx,%ebx
    7d28:	8b 4c 24 14          	mov    0x14(%esp),%ecx
    uintptr_t end_va = va + count;
    7d2c:	01 de                	add    %ebx,%esi
    va -= offset % SECTSIZE;
    7d2e:	89 c8                	mov    %ecx,%eax
    7d30:	25 ff 01 00 00       	and    $0x1ff,%eax
    7d35:	29 c3                	sub    %eax,%ebx
    for (; va < end_va; va += SECTSIZE, secno ++) {
    7d37:	39 f3                	cmp    %esi,%ebx
    7d39:	73 77                	jae    7db2 <readseg+0x92>
    uint32_t secno = (offset / SECTSIZE) + 1;
    7d3b:	c1 e9 09             	shr    $0x9,%ecx
    7d3e:	41                   	inc    %ecx
    asm volatile ("inb %1, %0" : "=a" (data) : "d" (port) : "memory");
    7d3f:	66 ba f7 01          	mov    $0x1f7,%dx
    7d43:	ec                   	in     (%dx),%al
    while ((inb(0x1F7) & 0xC0) != 0x40)
    7d44:	24 c0                	and    $0xc0,%al
    7d46:	0f b6 c0             	movzbl %al,%eax
    7d49:	83 f8 40             	cmp    $0x40,%eax
    7d4c:	75 f1                	jne    7d3f <readseg+0x1f>
    asm volatile ("outb %0, %1" :: "a" (data), "d" (port) : "memory");
    7d4e:	b0 01                	mov    $0x1,%al
    7d50:	66 ba f2 01          	mov    $0x1f2,%dx
    7d54:	ee                   	out    %al,(%dx)
    7d55:	66 ba f3 01          	mov    $0x1f3,%dx
    7d59:	88 c8                	mov    %cl,%al
    7d5b:	ee                   	out    %al,(%dx)
    7d5c:	66 ba f4 01          	mov    $0x1f4,%dx
    7d60:	88 e8                	mov    %ch,%al
    7d62:	ee                   	out    %al,(%dx)
    outb(0x1F5, (secno >> 16) & 0xFF);
    7d63:	89 c8                	mov    %ecx,%eax
    7d65:	c1 e8 10             	shr    $0x10,%eax
    7d68:	66 ba f5 01          	mov    $0x1f5,%dx
    7d6c:	ee                   	out    %al,(%dx)
    outb(0x1F6, ((secno >> 24) & 0xF) | 0xE0);
    7d6d:	89 c8                	mov    %ecx,%eax
    7d6f:	89 cd                	mov    %ecx,%ebp
    7d71:	c1 e8 18             	shr    $0x18,%eax
    7d74:	83 e0 0f             	and    $0xf,%eax
    7d77:	0d e0 00 00 00       	or     $0xe0,%eax
    7d7c:	66 ba f6 01          	mov    $0x1f6,%dx
    7d80:	ee                   	out    %al,(%dx)
    7d81:	b0 20                	mov    $0x20,%al
    asm volatile ("inb %1, %0" : "=a" (data) : "d" (port) : "memory");
    7d83:	66 ba f7 01          	mov    $0x1f7,%dx
    asm volatile ("outb %0, %1" :: "a" (data), "d" (port) : "memory");
    7d87:	ee                   	out    %al,(%dx)
    asm volatile ("inb %1, %0" : "=a" (data) : "d" (port) : "memory");
    7d88:	66 ba f7 01          	mov    $0x1f7,%dx
    7d8c:	ec                   	in     (%dx),%al
    while ((inb(0x1F7) & 0xC0) != 0x40)
    7d8d:	24 c0                	and    $0xc0,%al
    7d8f:	0f b6 c0             	movzbl %al,%eax
    7d92:	83 f8 40             	cmp    $0x40,%eax
    7d95:	75 f1                	jne    7d88 <readseg+0x68>
    asm volatile (
    7d97:	ba f0 01 00 00       	mov    $0x1f0,%edx
    7d9c:	b9 80 00 00 00       	mov    $0x80,%ecx
    7da1:	89 df                	mov    %ebx,%edi
    7da3:	fc                   	cld    
    7da4:	f2 6d                	repnz insl (%dx),%es:(%edi)
    for (; va < end_va; va += SECTSIZE, secno ++) {
    7da6:	81 c3 00 02 00 00    	add    $0x200,%ebx
    7dac:	39 f3                	cmp    %esi,%ebx
    7dae:	89 e9                	mov    %ebp,%ecx
    7db0:	72 8c                	jb     7d3e <readseg+0x1e>
}
    7db2:	5e                   	pop    %esi
    7db3:	5f                   	pop    %edi
    7db4:	5b                   	pop    %ebx
    7db5:	5d                   	pop    %ebp
    7db6:	c3                   	ret    
